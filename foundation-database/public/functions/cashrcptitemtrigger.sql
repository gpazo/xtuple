CREATE OR REPLACE FUNCTION _cashrcptitemtrigger()
  RETURNS trigger AS
$BODY$
-- Copyright (c) 1999-2015 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
-- Copyright (c) 2012 by OpenMFG LLC, d/b/a xTuple. 
--	# Modification for the Cash Receipt by Customer Group package
DECLARE
  _check      BOOLEAN;
  _openAmount NUMERIC;

BEGIN

  -- Checks
  -- Start with Privileges
  IF (TG_OP = 'INSERT') THEN
    SELECT checkPrivilege('MaintainCashReceipts') INTO _check;
    IF NOT (_check) THEN
      RAISE EXCEPTION 'You do not have privileges to add a new Cash Receipt Application.';
    END IF;
  ELSE
    SELECT checkPrivilege('MaintainCashReceipts') INTO _check;
    IF NOT (_check) THEN
      RAISE EXCEPTION 'You do not have privileges to alter a Cash Receipt Application.';
    END IF;
  END IF;

  -- Over Application
  SELECT round(currToCurr(aropen_curr_id, cashrcpt_curr_id,
               aropen_amount - aropen_paid, cashrcpt_distdate) -
               COALESCE((SELECT SUM(cashrcptitem_amount)
                           FROM cashrcptitem, cashrcpt
                           WHERE ((cashrcpt_id=cashrcptitem_cashrcpt_id)
                             AND  (NOT cashrcpt_void)
                             AND  (NOT cashrcpt_posted)
                             AND  (cashrcpt_id != NEW.cashrcptitem_cashrcpt_id)
                             AND  (cashrcptitem_aropen_id=NEW.cashrcptitem_aropen_id))), 0),2) INTO _openAmount
  FROM aropen, cashrcpt
  WHERE ( (aropen_id=NEW.cashrcptitem_aropen_id)
    AND   (cashrcpt_id=NEW.cashrcptitem_cashrcpt_id) );
  IF (NEW.cashrcptitem_amount > _openAmount) THEN
    RAISE EXCEPTION 'You may not apply more than the balance of this item.';
  END IF;

-- Add Customer number to the Cash Receipt Item  
  SELECT aropen_cust_id INTO NEW.cashrcptitem_cust_id
    FROM aropen WHERE aropen_id = NEW.cashrcptitem_aropen_id;	

  RETURN NEW;

END;
$BODY$
  LANGUAGE plpgsql;

