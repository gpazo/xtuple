SELECT xt.create_table('invcitemaccnt', 'public');
SELECT xt.add_column('invcitemaccnt','invcitemaccnt_id', 	  'SERIAL',  'NOT NULL', 'public');
SELECT xt.add_column('invcitemaccnt','invcitemaccnt_invchead_id', 'INTEGER', 'NULL', 'public');
SELECT xt.add_column('invcitemaccnt','invcitemaccnt_invcitem_id', 'INTEGER', 'NULL', 'public');
SELECT xt.add_column('invcitemaccnt','invcitemaccnt_accnt_id',    'INTEGER', 'NULL', 'public');
SELECT xt.add_constraint('invcitemaccnt', 'pk_invcitemaccnt', 'PRIMARY KEY (invcitemaccnt_id)', 'public');
SELECT xt.add_constraint('invcitemaccnt', 'fk_invcitemaccnt_invchead', 'FOREIGN KEY (invcitemaccnt_invchead_id) REFERENCES invchead (invchead_id)', 'public');
SELECT xt.add_constraint('invcitemaccnt', 'fk_invcitemaccnt_invcitem', 'FOREIGN KEY (invcitemaccnt_invcitem_id) REFERENCES invcitem (invcitem_id)', 'public');


