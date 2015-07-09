CREATE OR REPLACE VIEW creditmemoline AS 
 SELECT cmhead.cmhead_number AS memo_number, cmitem.cmitem_linenumber AS line_number, item.item_number, whsinfo.warehous_code AS recv_site, rsncode.rsncode_code AS reason_code, cmitem.cmitem_qtyreturned AS qty_returned, cmitem.cmitem_qtycredit AS qty_to_credit, COALESCE(qty_uom.uom_name, 'None'::text) AS qty_uom, cmitem.cmitem_unitprice AS net_unit_price, COALESCE(price_uom.uom_name, 'None'::text) AS price_uom, COALESCE(taxtype.taxtype_name, 'None'::text) AS tax_type, cmitem.cmitem_comments AS notes, 
        CASE
            WHEN cmitemaccnt.cmitemaccnt_accnt_id <> (-1) THEN ( SELECT accnt.accnt_name
               FROM accnt
              WHERE accnt.accnt_id = cmitemaccnt.cmitemaccnt_accnt_id)
            ELSE ''::text
        END AS override_accnt
   FROM cmitem
   LEFT JOIN cmhead ON cmitem.cmitem_cmhead_id = cmhead.cmhead_id
   LEFT JOIN itemsite ON itemsite.itemsite_id = cmitem.cmitem_itemsite_id
   LEFT JOIN item ON item.item_id = itemsite.itemsite_item_id
   LEFT JOIN whsinfo ON whsinfo.warehous_id = itemsite.itemsite_warehous_id
   LEFT JOIN rsncode ON rsncode.rsncode_id = cmitem.cmitem_rsncode_id
   LEFT JOIN taxtype ON taxtype.taxtype_id = cmitem.cmitem_taxtype_id
   LEFT JOIN uom qty_uom ON qty_uom.uom_id = cmitem.cmitem_qty_uom_id
   LEFT JOIN uom price_uom ON price_uom.uom_id = cmitem.cmitem_price_uom_id
   LEFT JOIN cmitemaccnt ON cmitemaccnt.cmitemaccnt_cmitem_id = cmitem.cmitem_id;

COMMENT ON VIEW creditmemoline IS 'Credit Memo Line';

-- Rule: "_DELETE" ON rcptbycustgrp.creditmemoline

-- DROP RULE "_DELETE" ON rcptbycustgrp.creditmemoline;

CREATE OR REPLACE RULE "_DELETE" AS
    ON DELETE TO creditmemoline DO INSTEAD  DELETE FROM cmitem
  WHERE cmitem.cmitem_cmhead_id = getcmheadid(old.memo_number, false) AND cmitem.cmitem_linenumber = old.line_number;

CREATE OR REPLACE FUNCTION insertcreditmemoline(creditmemoline)
  RETURNS boolean AS
$BODY$
-- Copyright (c) 1999-2011 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pNew ALIAS FOR $1;
  _check INTEGER;
  _r RECORD;

BEGIN
  SELECT cmhead_id INTO _check
  FROM cmhead
  WHERE (cmhead_id=getCmheadId(pNew.memo_number, FALSE));
  IF (NOT FOUND) THEN
    RAISE EXCEPTION 'Credit Memo # % not found', pNew.memo_number;
  END IF;

  INSERT INTO cmitem ( cmitem_cmhead_id,
                       cmitem_linenumber,
                       cmitem_itemsite_id,
                       cmitem_qtycredit,
                       cmitem_qtyreturned,
                       cmitem_unitprice,
                       cmitem_comments,
                       cmitem_rsncode_id,
                       cmitem_taxtype_id,
                       cmitem_qty_uom_id,
                       cmitem_qty_invuomratio,
                       cmitem_price_uom_id,
                       cmitem_price_invuomratio	)
  SELECT cmhead_id,
         COALESCE(pNew.line_number,
                  (SELECT (COALESCE(MAX(cmitem_linenumber), 0) + 1)
                   FROM cmitem WHERE (cmitem_cmhead_id=cmhead_id))),
         COALESCE(itemsite_id, -1),
         COALESCE(pNew.qty_to_credit, 0),
         COALESCE(pNew.qty_returned, 0),
         COALESCE(pNew.net_unit_price, 0),
         pNew.notes,
         getRsnId(pNew.reason_code),
         taxtype_id,
         COALESCE(getUomId(pNew.qty_uom), item_inv_uom_id),
         CASE
           WHEN item_id IS NOT NULL THEN itemuomtouomratio(item_id, COALESCE(getUomId(pNew.qty_uom),item_inv_uom_id),item_inv_uom_id)
           ELSE 1
         END,
         COALESCE(getUomId(pNew.price_uom),item_price_uom_id),
         CASE
           WHEN item_id IS NOT NULL THEN itemuomtouomratio(item_id, COALESCE(getUomId(pNew.price_uom),item_price_uom_id),item_price_uom_id)
           ELSE 1
        END
  FROM cmhead LEFT OUTER JOIN item ON (item_id=getItemId(pNew.item_number))
              LEFT OUTER JOIN itemsite ON (itemsite_item_id=item_id AND itemsite_warehous_id=getWarehousId(pNew.recv_site, 'ALL'))
              LEFT OUTER JOIN taxtype ON (taxtype_id=CASE WHEN pNew.tax_type IS NULL THEN getItemTaxType(item_id,cmhead_taxzone_id)
                                                          WHEN pNew.tax_type = 'None' THEN NULL
                                                          ELSE getTaxTypeId(pNew.tax_type)
                                                     END)
  WHERE (cmhead_id=getCmheadId(pNew.memo_number, FALSE));

-- RCPTBYCUSTGRP - Update Override Revenue Account
   INSERT INTO cmitemaccnt (cmitemaccnt_cmhead_id, cmitemaccnt_cmitem_id, cmitemaccnt_accnt_id)
       SELECT cmhead_id, cmitem_id, pNew.override_accnt
		  FROM cmhead JOIN cmitem ON cmhead_id=cmitem_cmhead_id
		  WHERE ((cmhead_number=pNew.memo_number) 
		    AND (cmitem_linenumber=pNew.line_number));   

  RETURN TRUE;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION insertcreditmemoline(creditmemoline) OWNER TO "admin";

-- Rule: "_INSERT" ON rcptbycustgrp.creditmemoline

-- DROP RULE "_INSERT" ON rcptbycustgrp.creditmemoline;

CREATE OR REPLACE RULE "_INSERT" AS
    ON INSERT TO creditmemoline DO INSTEAD  SELECT insertcreditmemoline(new.*) AS insertcreditmemoline;

CREATE OR REPLACE FUNCTION updatecreditmemoline(creditmemoline, creditmemoline)
  RETURNS boolean AS
$BODY$
-- Copyright (c) 1999-2011 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pNew ALIAS FOR $1;
  pOld ALIAS FOR $2;
  _check INTEGER;
  _r     RECORD;
  _tmp   INTEGER;

BEGIN
  SELECT cmitem_id INTO _check
  FROM cmitem
  WHERE ( (cmitem_cmhead_id=getCmheadId(pOld.memo_number, FALSE)) AND (cmitem_linenumber=pOld.line_number) );
  IF (NOT FOUND) THEN
    RAISE EXCEPTION 'Credit Memo # % Line Number # not found', pOld.memo_number, pOld.line_number;
  END IF;

  UPDATE cmitem
    SET cmitem_itemsite_id=COALESCE(itemsite_id, -1),
        cmitem_qtycredit=pNew.qty_to_credit,
        cmitem_qtyreturned=pNew.qty_returned,
        cmitem_unitprice=pNew.net_unit_price,
        cmitem_comments=pNew.notes,
        cmitem_rsncode_id=getRsnId(pNew.reason_code),
        cmitem_taxtype_id=taxtype_id,
        cmitem_qty_uom_id=COALESCE(getUomId(pNew.qty_uom), item_inv_uom_id),
        cmitem_qty_invuomratio=CASE WHEN item_id IS NOT NULL THEN itemuomtouomratio(item_id, COALESCE(getUomId(pNew.qty_uom),item_inv_uom_id),item_inv_uom_id)
                                    ELSE 1
                               END,
        cmitem_price_uom_id=COALESCE(getUomId(pNew.price_uom),item_price_uom_id),
        cmitem_price_invuomratio=CASE WHEN item_id IS NOT NULL THEN itemuomtouomratio(item_id, COALESCE(getUomId(pNew.price_uom),item_price_uom_id),item_price_uom_id)
                                      ELSE 1
                                 END
  FROM cmhead LEFT OUTER JOIN item ON (item_id=getItemId(pNew.item_number))
              LEFT OUTER JOIN itemsite ON (itemsite_item_id=item_id AND
                                           itemsite_warehous_id=getWarehousId(pNew.recv_site, 'ALL'))
              LEFT OUTER JOIN taxtype ON (taxtype_id=CASE WHEN pNew.tax_type IS NULL THEN getItemTaxType(item_id,cmhead_taxzone_id)
                                                          WHEN pNew.tax_type = 'None' THEN NULL
                                                          ELSE getTaxTypeId(pNew.tax_type)
                                                     END)
  WHERE cmitem_cmhead_id=cmhead_id
    AND cmhead_number=pOld.memo_number
    AND cmitem_linenumber=pOld.line_number
    AND cmhead_posted=FALSE;

--  RCPTBYCUSTGRP - Update Credit Memo Item override Account
	SELECT cmitemaccnt_id INTO _tmp FROM cmitemaccnt 
		WHERE cmitemaccnt_cmitem_id = (SELECT cmitem_id from cmhead, cmitem
				WHERE cmhead_id=cmitem_cmhead_id 
				  AND cmhead_memonumber = pOld.memo_number
				  AND cmitem_linenumber = pOld.line_number);
	IF (NOT FOUND) THEN

	   INSERT INTO cmitemaccnt (cmitemaccnt_cmhead_id, cmitemaccnt_cmitem_id, cmitemaccnt_accnt_id)
		SELECT cmhead_id, cmitem_id, pNew.override_accnt
		  FROM cmhead JOIN cmitem ON cmhead_id=cmitem_cmhead_id
		  WHERE ((cmhead_number=pNew.memo_number) 
		    AND (cmitem_linenumber=pNew.line_number)); 
	ELSE	    

	   UPDATE cmitemaccnt SET cmitemaccnt_accnt_id = pNew.override_accnt
		WHERE cmitemaccnt_cmitem_id = (SELECT cmitem_id from cmhead, cmitem
				WHERE cmhead_id=cmitem_cmhead_id 
				  AND cmhead_memonumber = pOld.memo_number
				  AND cmitem_linenumber = pOld.line_number);
	END IF;
	
  RETURN TRUE;
END;
$BODY$
  LANGUAGE plpgsql;

CREATE OR REPLACE RULE "_UPDATE" AS
    ON UPDATE TO creditmemoline DO INSTEAD  SELECT updatecreditmemoline(new.*, old.*) AS updatecreditmemoline;

