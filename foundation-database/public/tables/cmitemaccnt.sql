SELECT xt.create_table('cmitemaccnt', 	'public');
SELECT xt.add_column('cmitemaccnt', 'cmitemaccnt_id', 		'SERIAL', 'NOT NULL', 'public');
SELECT xt.add_column('cmitemaccnt', 'cmitemaccnt_cmhead_id',   'INTEGER', 'NULL', 'public');
SELECT xt.add_column('cmitemaccnt', 'cmitemaccnt_cmitem_id',	'INTEGER', 'NULL', 'public');
SELECT xt.add_column('cmitemaccnt', 'cmitemaccnt_accnt_id',	'INTEGER', 'NULL', 'public');
SELECT xt.add_constraint('cmitemaccnt', 'pk_cmitemaccnt', 	 'PRIMARY KEY (cmitemaccnt_id)', 				      'public');
SELECT xt.add_constraint('cmitemaccnt', 'fk_cmitemaccnt_cmhead', 'FOREIGN KEY (cmitemaccnt_cmhead_id) REFERENCES cmhead (cmhead_id)', 'public');
SELECT xt.add_constraint('cmitemaccnt', 'fk_cmitemaccnt_cmitem', 'FOREIGN KEY (cmitemaccnt_cmitem_id) REFERENCES cmitem (cmitem_id)', 'public');
