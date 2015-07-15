var _ = require("underscore"),
  assert = require('chai').assert,
  path = require('path');

(function () {
  "use strict";
  describe('numOfDatabaseUsers()', function () {

    var loginData = require(path.join(__dirname, "../../lib/login_data.js")).data,
      datasource = require('../../../node-datasource/lib/ext/datasource').dataSource,
      config = require(path.join(__dirname, "../../../node-datasource/config.js")),
      creds = _.extend({}, config.databaseServer, {database: loginData.org});

    it("with no args should return without error", function (done) {
      var sql = "select numOfDatabaseUsers() as result;";
      datasource.query(sql, creds, function (err, res) {
        assert.isNull(err);
        done();
      });
    });

    it("should return 0 with an outrageous argument", function (done) {
      var sql = "select numOfDatabaseUsers('this cannot be right') as result;";
      datasource.query(sql, creds, function (err, res) {
        assert.isNull(err);
        assert.equal(res.rows[0].result, 0);
        done();
      });
    });

    it("should return non-negative with a reasonable argument", function (done) {
      var sql = "select numOfDatabaseUsers('xTuple ERP') as result;";
      datasource.query(sql, creds, function (err, res) {
        assert.isNull(err);
        assert(res.rows[0].result >= 0);
        done();
      });
    });
  });
}());
