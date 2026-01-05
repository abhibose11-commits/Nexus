/*
================================================================================
STORED PROCEDURE: SP_GENERATE_COLUMN_MAPPING_TO_TABLE
================================================================================
Purpose: Generate column-level lineage mapping and save to a target table
         Shows actual source table and column names (not aliases)

Usage:
  -- Generate mappings and save to default table
  CALL SP_GENERATE_COLUMN_MAPPING_TO_TABLE('SCHEMA.VIEW_NAME', 'TARGET_SCHEMA.MAPPING_TABLE');
  
  -- Multiple views
  CALL SP_GENERATE_COLUMN_MAPPING_TO_TABLE(
      'SCHEMA.VIEW1, SCHEMA.VIEW2', 
      'MY_SCHEMA.EDW_COLUMN_MAPPINGS'
  );

Parameters:
  - VIEW_LIST: Comma-separated list of view names to document
  - OUTPUT_TABLE: Fully qualified table name to store results (will be replaced)

================================================================================
*/

CREATE OR REPLACE PROCEDURE SP_GENERATE_COLUMN_MAPPING_TO_TABLE(
    VIEW_LIST VARCHAR,
    OUTPUT_TABLE VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
import re
from dataclasses import dataclass, field
from typing import Dict, List, Tuple, Optional

@dataclass
class ColumnMapping:
    target_table: str
    target_column: str
    source_table: str
    source_column: str
    transformation_logic: str
    cte_chain: str = ""

@dataclass
class CTEDefinition:
    name: str
    sql: str
    columns: Dict[str, str] = field(default_factory=dict)
    source_tables: List[str] = field(default_factory=list)

class SQLLineageParser:
    def __init__(self, sql_text: str, target_table: str = None):
        self.sql_text = sql_text.strip()
        self.target_table = target_table or self._extract_target_name()
        self.ctes: Dict[str, CTEDefinition] = {}
        self.final_select_columns: Dict[str, str] = {}
        self.final_source_tables: List[str] = []
        self.mappings: List[ColumnMapping] = []
        
    def _extract_target_name(self) -> str:
        match = re.search(r'CREATE\s+(?:OR\s+REPLACE\s+)?(?:SECURE\s+)?VIEW\s+(?:IF\s+NOT\s+EXISTS\s+)?([^\s(]+)', 
                         self.sql_text, re.IGNORECASE)
        return match.group(1).strip().strip('"\'') if match else "UNKNOWN"
    
    def parse(self) -> List[ColumnMapping]:
        self._parse_all_subqueries()
        self._extract_final_select()
        self._build_lineage()
        return self.mappings
    
    def _find_matching_paren(self, sql: str, start: int) -> int:
        if start >= len(sql) or sql[start] != '(':
            return -1
        depth, pos = 1, start + 1
        in_str, str_char = False, None
        while pos < len(sql) and depth > 0:
            c = sql[pos]
            if c in ("'", '"') and (pos == 0 or sql[pos-1] != '\\'):
                if not in_str:
                    in_str, str_char = True, c
                elif c == str_char:
                    in_str = False
            if not in_str:
                if c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
            pos += 1
        return pos - 1 if depth == 0 else -1
    
    def _parse_all_subqueries(self):
        sql = self.sql_text
        subqueries = []
        pos = 0
        while pos < len(sql):
            paren_pos = sql.find('(', pos)
            if paren_pos == -1:
                break
            after = sql[paren_pos + 1:].lstrip()
            if after.upper().startswith('SELECT'):
                end = self._find_matching_paren(sql, paren_pos)
                if end > paren_pos:
                    inner_sql = sql[paren_pos + 1:end].strip()
                    after_close = sql[end + 1:].strip()
                    alias_match = re.match(r'^(?:AS\s+)?(\w+)', after_close, re.IGNORECASE)
                    if alias_match:
                        alias = alias_match.group(1).upper()
                        if alias not in ('ON', 'WHERE', 'AND', 'OR', 'INNER', 'LEFT', 'RIGHT', 
                                        'FULL', 'CROSS', 'JOIN', 'GROUP', 'ORDER', 'HAVING', 'UNION', 'LIMIT'):
                            subqueries.append({'alias': alias, 'sql': inner_sql, 'depth': sql[:paren_pos].count('(')})
                    pos = paren_pos + 1
                else:
                    pos = paren_pos + 1
            else:
                pos = paren_pos + 1
        subqueries.sort(key=lambda x: x['depth'], reverse=True)
        for sq in subqueries:
            self._store_subquery(sq['alias'], sq['sql'])
    
    def _store_subquery(self, name: str, sql: str):
        if name in self.ctes:
            return
        cte = CTEDefinition(name=name, sql=sql)
        cte.columns = self._extract_columns(sql)
        if '*' in cte.columns and len(cte.columns) == 1:
            inner_cols = self._get_inner_columns(sql)
            if inner_cols:
                cte.columns = inner_cols['columns']
                cte.source_tables = inner_cols.get('sources', [])
            else:
                cte.source_tables = self._extract_sources(sql)
        else:
            cte.source_tables = self._extract_sources(sql)
        self.ctes[name] = cte
    
    def _get_inner_columns(self, sql: str) -> Optional[Dict]:
        match = re.search(r'\bSELECT\s+\*\s+FROM\s*\(', sql, re.IGNORECASE)
        if not match:
            return None
        paren_start = sql.rfind('(', 0, match.end())
        if paren_start == -1:
            paren_start = sql.find('(', match.start())
        if paren_start == -1:
            return None
        end = self._find_matching_paren(sql, paren_start)
        if end <= paren_start:
            return None
        inner = sql[paren_start + 1:end].strip()
        cols = self._extract_columns(inner)
        if cols and '*' not in cols:
            sources = self._extract_sources(inner)
            return {'columns': cols, 'sources': sources}
        return None
    
    def _extract_columns(self, sql: str) -> Dict[str, str]:
        columns = {}
        match = re.search(r'\bSELECT\s+(.*?)\s+FROM\b', sql, re.IGNORECASE | re.DOTALL)
        if not match:
            return columns
        select_part = match.group(1).strip()
        if select_part == '*':
            return {'*': '*'}
        parts = self._split_by_comma(select_part)
        for part in parts:
            part = part.strip()
            if not part:
                continue
            alias, expr = self._parse_column(part)
            if alias:
                columns[alias.upper()] = expr
        return columns
    
    def _split_by_comma(self, text: str) -> List[str]:
        parts, current, depth = [], [], 0
        in_str, str_char = False, None
        for i, c in enumerate(text):
            if c in ("'", '"') and (i == 0 or text[i-1] != '\\'):
                if not in_str:
                    in_str, str_char = True, c
                elif c == str_char:
                    in_str = False
            if not in_str:
                if c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
                elif c == ',' and depth == 0:
                    parts.append(''.join(current).strip())
                    current = []
                    continue
            current.append(c)
        if current:
            parts.append(''.join(current).strip())
        return parts
    
    def _parse_column(self, expr: str) -> Tuple[str, str]:
        expr = expr.strip()
        expr = re.sub(r'--[^\n]*\n', '', expr).strip()
        m = re.search(r'^(.*?)\s+AS\s+["\']?(\w+)["\']?\s*$', expr, re.IGNORECASE | re.DOTALL)
        if m:
            return m.group(2), m.group(1).strip()
        m = re.search(r'^(.+?)\s+([A-Za-z_]\w*)$', expr, re.DOTALL)
        if m:
            alias = m.group(2)
            kws = {'AND', 'OR', 'NOT', 'NULL', 'TRUE', 'FALSE', 'END', 'THEN', 'ELSE', 
                   'WHEN', 'CASE', 'IS', 'AS', 'IN', 'ON', 'BY', 'ASC', 'DESC'}
            if alias.upper() not in kws:
                return alias, m.group(1).strip()
        m = re.match(r'^(?:(\w+)\.)?(\w+)$', expr)
        if m:
            return m.group(2), expr
        return None, expr
    
    def _extract_sources(self, sql: str) -> List[str]:
        sources = []
        sql = re.sub(r';.*$', '', sql)
        for m in re.finditer(r'\bFROM\s+([A-Za-z_][\w.]*)\s*(?:AS\s+)?(\w+)?', sql, re.IGNORECASE):
            table = m.group(1).upper()
            alias = (m.group(2) or table).upper()
            sources.append(f"{table} ({alias})" if alias != table else table)
        for m in re.finditer(r'\bJOIN\s+([A-Za-z_][\w.]*)\s*(?:AS\s+)?(\w+)?\s+ON', sql, re.IGNORECASE):
            table = m.group(1).upper()
            alias = (m.group(2) or table).upper()
            sources.append(f"{table} ({alias})" if alias != table else table)
        return sources
    
    def _extract_final_select(self):
        sql = self.sql_text
        m = re.search(r'\bAS\s*\n?\s*(SELECT\b.*)', sql, re.IGNORECASE | re.DOTALL)
        if m:
            sql = m.group(1)
        self.final_select_columns = self._extract_columns(sql)
        self.final_source_tables = self._extract_sources(sql)
        if '*' in self.final_select_columns and self.final_source_tables:
            src = self.final_source_tables[0].split('(')[0].strip().upper()
            if src in self.ctes:
                del self.final_select_columns['*']
                for col in self.ctes[src].columns:
                    self.final_select_columns[col] = f"{src.lower()}.{col.lower()}"
    
    def _build_lineage(self):
        for col_name, col_expr in self.final_select_columns.items():
            if not col_name:
                continue
            mapping = ColumnMapping(
                target_table=self.target_table,
                target_column=col_name,
                source_table="",
                source_column="",
                transformation_logic=col_expr,
                cte_chain=""
            )
            context_cte = None
            alias_match = re.match(r'^(\w+)\.', col_expr)
            if alias_match:
                context_cte = self._resolve_alias(alias_match.group(1).upper(), None)
            traced = self._trace(col_expr, set(), 0, context_cte)
            mapping.source_table = traced['table']
            mapping.source_column = traced['column']
            mapping.cte_chain = traced['chain']
            if mapping.cte_chain:
                first_cte = mapping.cte_chain.split(' → ')[0].strip().upper()
                if first_cte in self.ctes and col_name in self.ctes[first_cte].columns:
                    mapping.transformation_logic = self.ctes[first_cte].columns[col_name]
            if mapping.transformation_logic.lower() == col_name.lower():
                mapping.transformation_logic = "Direct mapping"
            self.mappings.append(mapping)
    
    def _trace(self, expr: str, visited: set, depth: int = 0, context_cte: str = None) -> Dict:
        result = {'table': '', 'column': '', 'chain': ''}
        if depth > 20:
            return result
        expr = expr.strip()
        m = re.match(r'^(\w+)\.(\w+)$', expr)
        if m:
            alias, col = m.group(1).upper(), m.group(2).upper()
            resolved = self._resolve_alias(alias, context_cte)
            if resolved in self.ctes and resolved not in visited:
                visited.add(resolved)
                cte = self.ctes[resolved]
                if col in cte.columns:
                    src_expr = cte.columns[col]
                    nested = self._trace(src_expr, visited.copy(), depth + 1, resolved)
                    if nested['table']:
                        result['table'] = nested['table']
                        result['column'] = nested['column']
                    else:
                        result['column'] = self._extract_actual_col(src_expr)
                        expr_alias = self._get_alias_from_expr(src_expr)
                        if expr_alias:
                            base_table = self._resolve_alias_to_base(expr_alias, resolved)
                            result['table'] = base_table
                        if not result['table'] or result['table'] in self.ctes:
                            for src in cte.source_tables:
                                tbl = src.split('(')[0].strip().upper()
                                if tbl not in self.ctes:
                                    result['table'] = tbl
                                    break
                    result['chain'] = resolved + (' → ' + nested['chain'] if nested['chain'] else '')
                else:
                    for src in cte.source_tables:
                        tbl = src.split('(')[0].strip().upper()
                        if tbl not in self.ctes:
                            result['table'] = tbl
                            result['column'] = col
                            break
                    result['chain'] = resolved
            else:
                result['table'] = resolved
                result['column'] = col
        else:
            refs = re.findall(r'(\w+)\.(\w+)', expr)
            if refs:
                tables, cols, chains = [], [], []
                for alias, col in refs:
                    single = self._trace(f"{alias}.{col}", visited.copy(), depth + 1, context_cte)
                    if single['table']:
                        tables.append(single['table'])
                    cols.append(single['column'] or col.upper())
                    if single['chain']:
                        chains.append(single['chain'])
                result['table'] = ', '.join(dict.fromkeys(tables))
                result['column'] = ', '.join(dict.fromkeys(cols))
                result['chain'] = ' + '.join(dict.fromkeys(chains))
            else:
                col_name = self._extract_actual_col(expr)
                if context_cte and context_cte in self.ctes:
                    cte = self.ctes[context_cte]
                    nested_result = self._trace_through_nested(col_name.upper(), cte.sql, visited.copy(), depth + 1)
                    if nested_result['table'] or nested_result['column']:
                        return nested_result
                result['column'] = col_name
        return result
    
    def _trace_through_nested(self, col_name: str, sql: str, visited: set, depth: int) -> Dict:
        result = {'table': '', 'column': '', 'chain': ''}
        if depth > 20:
            return result
        col_name = col_name.upper()
        pos = 0
        while pos < len(sql):
            paren_pos = sql.find('(', pos)
            if paren_pos == -1:
                break
            after = sql[paren_pos + 1:].lstrip()
            if after.upper().startswith('SELECT'):
                end = self._find_matching_paren(sql, paren_pos)
                if end > paren_pos:
                    inner_sql = sql[paren_pos + 1:end].strip()
                    inner_cols = self._extract_columns(inner_sql)
                    if col_name in inner_cols:
                        src_expr = inner_cols[col_name]
                        m = re.match(r'^(\w+)\.(\w+)$', src_expr.strip())
                        if m:
                            alias = m.group(1).upper()
                            actual_col = m.group(2).upper()
                            inner_sources = self._extract_sources(inner_sql)
                            for src in inner_sources:
                                match = re.match(r'([^\s(]+)\s*\((\w+)\)', src)
                                if match and match.group(2).upper() == alias:
                                    result['table'] = match.group(1).upper()
                                    result['column'] = actual_col
                                    return result
                            for src in inner_sources:
                                tbl = src.split('(')[0].strip().upper()
                                tbl_short = tbl.split('.')[-1] if '.' in tbl else tbl
                                if tbl_short == alias or tbl == alias:
                                    result['table'] = tbl
                                    result['column'] = actual_col
                                    return result
                        else:
                            actual_col = self._extract_actual_col(src_expr)
                            if actual_col != col_name:
                                nested = self._trace_through_nested(actual_col, inner_sql, visited, depth + 1)
                                if nested['table']:
                                    return nested
                                inner_sources = self._extract_sources(inner_sql)
                                for src in inner_sources:
                                    tbl = src.split('(')[0].strip().upper()
                                    if tbl not in self.ctes:
                                        result['table'] = tbl
                                        result['column'] = actual_col
                                        return result
                    pos = paren_pos + 1
                else:
                    pos = paren_pos + 1
            else:
                pos = paren_pos + 1
        return result
    
    def _resolve_alias_to_base(self, alias: str, context_cte: str) -> str:
        alias = alias.upper()
        visited = set()
        return self._resolve_alias_recursive(alias, context_cte, visited)
    
    def _resolve_alias_recursive(self, alias: str, context_cte: str, visited: set) -> str:
        if alias in visited:
            return alias
        visited.add(alias)
        if context_cte and context_cte in self.ctes:
            cte = self.ctes[context_cte]
            for src in cte.source_tables:
                m = re.match(r'([^\s(]+)\s*\((\w+)\)', src)
                if m:
                    tbl = m.group(1).upper()
                    src_alias = m.group(2).upper()
                    if src_alias == alias:
                        if tbl in self.ctes:
                            for inner_src in self.ctes[tbl].source_tables:
                                inner_tbl = inner_src.split('(')[0].strip().upper()
                                if inner_tbl not in self.ctes:
                                    return inner_tbl
                            return self._resolve_alias_recursive(tbl, tbl, visited)
                        return tbl
        for cte_name, cte in self.ctes.items():
            if cte_name in visited:
                continue
            for src in cte.source_tables:
                m = re.match(r'([^\s(]+)\s*\((\w+)\)', src)
                if m and m.group(2).upper() == alias:
                    tbl = m.group(1).upper()
                    if tbl in self.ctes:
                        result = self._resolve_alias_recursive(tbl, tbl, visited)
                        if result not in self.ctes:
                            return result
                    else:
                        return tbl
        return alias
    
    def _resolve_alias(self, alias: str, context_cte: str = None) -> str:
        alias = alias.upper()
        if context_cte and context_cte in self.ctes:
            for src in self.ctes[context_cte].source_tables:
                m = re.match(r'([^\s(]+)\s*\((\w+)\)', src)
                if m and m.group(2).upper() == alias:
                    return m.group(1).upper()
        if alias in self.ctes:
            return alias
        for cte in self.ctes.values():
            for src in cte.source_tables:
                m = re.match(r'([^\s(]+)\s*\((\w+)\)', src)
                if m and m.group(2).upper() == alias:
                    return m.group(1).upper()
        return alias
    
    def _extract_actual_col(self, expr: str) -> str:
        expr = expr.strip()
        m = re.match(r'^\w+\.(\w+)$', expr)
        if m:
            return m.group(1).upper()
        m = re.match(r'^(\w+)$', expr)
        if m:
            return m.group(1).upper()
        m = re.search(r'\b\w+\.(\w+)\b', expr)
        if m:
            return m.group(1).upper()
        kws = {'TRIM', 'UPPER', 'LOWER', 'COALESCE', 'NVL', 'CAST', 'DECODE', 'IFF',
               'AS', 'CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'AND', 'OR', 'NOT', 'NULL',
               'IS', 'IN', 'TO_DATE', 'TO_CHAR', 'ROW_NUMBER', 'OVER', 'PARTITION', 'ORDER', 'BY'}
        words = re.findall(r'\b(\w+)\b', expr)
        for w in reversed(words):
            if w.upper() not in kws and not w.isdigit():
                return w.upper()
        return expr.upper()[:50]
    
    def _get_alias_from_expr(self, expr: str) -> Optional[str]:
        m = re.search(r'\b(\w+)\.\w+', expr)
        return m.group(1).upper() if m else None


def run(session, view_list: str, output_table: str):
    """Main entry point - generates mappings and saves to table."""
    
    # Parse view list
    views = [v.strip() for v in view_list.split(',') if v.strip()]
    
    all_results = []
    processed = 0
    errors = 0
    
    for view_name in views:
        try:
            # Get view DDL
            ddl_query = f"SELECT GET_DDL('VIEW', '{view_name}')"
            ddl_result = session.sql(ddl_query).collect()
            
            if ddl_result and ddl_result[0][0]:
                ddl = ddl_result[0][0]
                
                # Parse the view
                parser = SQLLineageParser(ddl, view_name)
                mappings = parser.parse()
                
                # Add to results
                for m in mappings:
                    all_results.append({
                        'TARGET_TABLE': m.target_table,
                        'TARGET_COLUMN': m.target_column,
                        'SOURCE_TABLE': m.source_table or '',
                        'SOURCE_COLUMN': m.source_column or '',
                        'TRANSFORMATION_LOGIC': (m.transformation_logic or '')[:4000],
                        'CTE_CHAIN': m.cte_chain or ''
                    })
                processed += 1
            else:
                all_results.append({
                    'TARGET_TABLE': view_name,
                    'TARGET_COLUMN': 'ERROR',
                    'SOURCE_TABLE': '',
                    'SOURCE_COLUMN': 'Could not retrieve DDL',
                    'TRANSFORMATION_LOGIC': '',
                    'CTE_CHAIN': ''
                })
                errors += 1
                
        except Exception as e:
            all_results.append({
                'TARGET_TABLE': view_name,
                'TARGET_COLUMN': 'ERROR',
                'SOURCE_TABLE': '',
                'SOURCE_COLUMN': str(e)[:200],
                'TRANSFORMATION_LOGIC': '',
                'CTE_CHAIN': ''
            })
            errors += 1
    
    # Save to table
    import pandas as pd
    if all_results:
        df = session.create_dataframe(pd.DataFrame(all_results))
        df.write.mode("overwrite").save_as_table(output_table)
        
        total_columns = len([r for r in all_results if r['TARGET_COLUMN'] != 'ERROR'])
        return f"SUCCESS: Processed {processed} views, {total_columns} columns mapped, {errors} errors. Results saved to {output_table}"
    else:
        return f"ERROR: No views processed"
$$;

/*
================================================================================
USAGE EXAMPLES
================================================================================

-- Example 1: Single view, save to table
CALL SP_GENERATE_COLUMN_MAPPING_TO_TABLE(
    'CORP_DESIGN_ISC.VW_BOM_STPO_STKO_BRP',
    'CORP_DESIGN_ISC.COLUMN_MAPPINGS'
);

-- Then query the results
SELECT * FROM CORP_DESIGN_ISC.COLUMN_MAPPINGS ORDER BY TARGET_TABLE, TARGET_COLUMN;

-- Example 2: Multiple views
CALL SP_GENERATE_COLUMN_MAPPING_TO_TABLE(
    'STG.V_INVENTORY_FACT, STG.V_DIM_MATERIAL, STG.V_DIM_PLANT',
    'STG.ALL_VIEW_MAPPINGS'
);

-- Example 3: Create a nice report
SELECT 
    TARGET_TABLE,
    TARGET_COLUMN,
    SOURCE_TABLE,
    SOURCE_COLUMN,
    CASE 
        WHEN TRANSFORMATION_LOGIC = 'Direct mapping' THEN '→'
        ELSE TRANSFORMATION_LOGIC 
    END AS TRANSFORM
FROM CORP_DESIGN_ISC.COLUMN_MAPPINGS
ORDER BY TARGET_TABLE, TARGET_COLUMN;

================================================================================
*/
