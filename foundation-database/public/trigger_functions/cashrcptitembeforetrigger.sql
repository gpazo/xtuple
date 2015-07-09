CREATE TRIGGER cashrcptitembeforetrigger
  BEFORE INSERT OR UPDATE
  ON cashrcptitem
  FOR EACH ROW
  EXECUTE PROCEDURE _cashrcptitemtrigger();

