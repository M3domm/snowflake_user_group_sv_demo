# Snowflake Semantic View — RLS/CLS Governance Demo

A self-contained SQL script for a live user group demo: a fact table + three
dimensions with generated dummy data, a Semantic View with comments,
synonyms, sample values, metrics, and a verified query and Row Access
Policy (RLS) + Column-level masking (CLS) applied to the *underlying tables*,
enforced automatically when queried through the semantic view.

## What it builds

1. A role hierarchy following Snowflake's access-control best practices
   (USERADMIN / SECURITYADMIN / SYSADMIN, custom roles rolled up under
   SYSADMIN, ACCOUNTADMIN untouched after initial grants).
2. `FCT_SALES` + `DIM_CUSTOMER` / `DIM_PRODUCT` / `DIM_REGION`, loaded with
   ~20,000 generated sales rows across 500 customers, 60 products, 6 regions.
3. A Semantic View (`SV_SALES_PERFORMANCE`) on top, with table/column
   comments, synonyms, sample values / enums, a derived metric, and one
   `AI_VERIFIED_QUERIES` entry.
4. A row access policy on the fact table and masking policies on the
   customer dimension — created by a separate governance role, applied by
   the table-owning role, and never touched on the semantic view itself
   (semantic views don't support policies directly).
5. Three consumer roles that only ever get `SELECT` on the semantic view —
   never on the base tables — to show that querying through the semantic
   view still inherits RLS/CLS from below.

## How to run it

Run `semantic_view_demo.sql` top to bottom in a Snowflake worksheet, using
a role that can reach `USERADMIN`/`SECURITYADMIN`/`SYSADMIN` (or run each
`USE ROLE` step as the appropriate admin). The script is organized into
`PART 1`–`PART 8` sections with banner comments — each is a natural
stopping point if you want to run it live, section by section.

Before running, replace the `<YOUR_USERNAME>` placeholders in Part 1 with
your actual Snowflake login (`SELECT CURRENT_USER();`) so the demo roles
get granted to you.

An optional teardown block is commented out at the end of the script.

## Requirements

- Snowflake Enterprise Edition or higher (row access policies, masking
  policies, and Semantic Views all require it).
- A role chain that can reach `USERADMIN`, `SECURITYADMIN`, and `SYSADMIN`.

## Sources

Written against Snowflake's official documentation:

- [Best practices for modeling semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/best-practices-modeling)
- [Using SQL commands to create and manage semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/sql)
- [Best practices for developing and deploying semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/best-practices-dev)
- [CREATE SEMANTIC VIEW reference](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
- [Access control considerations](https://docs.snowflake.com/en/user-guide/security-access-control-considerations)
- [Row access policies](https://docs.snowflake.com/en/user-guide/security-row-intro)
- [Column-level security](https://docs.snowflake.com/en/user-guide/security-column-intro)
