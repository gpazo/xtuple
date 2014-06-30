/*jshint node:true, indent:2, curly:false, eqeqeq:true, immed:true, latedef:true, newcap:true, noarg:true,
regexp:true, undef:true, strict:true, trailing:true, white:true */
/*global Backbone:true, _:true, XM:true, XT:true*/

var _ = require('underscore'),
  async = require('async'),
  buildDatabase = require("./build_database"),
  buildDatabaseUtil = require("./build_database_util"),
  buildClient = require("./build_client").buildClient,
  dataSource = require('../../node-datasource/lib/ext/datasource').dataSource,
  exec = require('child_process').exec,
  fs = require('fs'),
  npm = require('npm'),
  path = require('path'),
  unregister = buildDatabaseUtil.unregister,
  winston = require('winston');

/*
  This is the point of entry for both the lightweight CLI entry-point and
  programmatic calls to build, such as from mocha. Most of the work in this
  file is in determining what the defaults mean. For example, if the
  user does not specify an extension, we install the core and all registered
  extensions, which requires a call to xt.ext.

  We delegate the work of actually building the database and building the
  client to build_database.js and build_client.js.
*/

(function () {
  "use strict";

  var creds;


  exports.build = function (options, callback) {
    var buildSpecs = {},
      databases = [],
      extension,
      //
      // Looks in a database to see which extensions are registered, and
      // tacks onto that list the core directories.
      //
      getRegisteredExtensions = function (database, callback) {
        var result,
          credsClone = JSON.parse(JSON.stringify(creds)),
          existsSql = "select relname from pg_class where relname = 'ext'",
          preInstallSql = "select xt.js_init();update xt.ext set ext_location = '/core-extensions' " +
            "where ext_name = 'oauth2' and ext_location = '/xtuple-extensions';",
          extSql = preInstallSql + "SELECT * FROM xt.ext ORDER BY ext_load_order",
          defaultExtensions = [
            { ext_location: '/core-extensions', ext_name: 'crm' },
            { ext_location: '/core-extensions', ext_name: 'project' },
            { ext_location: '/core-extensions', ext_name: 'sales' },
            { ext_location: '/core-extensions', ext_name: 'billing' },
            { ext_location: '/core-extensions', ext_name: 'purchasing' },
            { ext_location: '/core-extensions', ext_name: 'oauth2' }
          ],
          adaptExtensions = function (err, res) {
            if (err) {
              callback(err);
              return;
            }

            var paths = _.map(_.compact(res.rows), function (row) {
              var location = row.ext_location,
                name = row.ext_name,
                extPath;

              if (location === '/core-extensions') {
                extPath = path.join(__dirname, "/../../enyo-client/extensions/source/", name);
              } else if (location === '/xtuple-extensions') {
                extPath = path.join(__dirname, "../../../xtuple-extensions/source", name);
              } else if (location === '/private-extensions') {
                extPath = path.join(__dirname, "../../../private-extensions/source", name);
              } else if (location === 'npm') {
                extPath = path.join(__dirname, "../../node_modules", name);
              }
              return extPath;
            });

            paths.unshift(path.join(__dirname, "../../enyo-client")); // core path
            paths.unshift(path.join(__dirname, "../../lib/orm")); // lib path
            paths.unshift(path.join(__dirname, "../../foundation-database")); // foundation path
            callback(null, {
              extensions: _.compact(paths),
              database: database,
              keepSql: options.keepSql,
              populateData: options.populateData,
              wipeViews: options.wipeViews,
              clientOnly: options.clientOnly,
              databaseOnly: options.databaseOnly
            });
          };

        credsClone.database = database;
        dataSource.query(existsSql, credsClone, function (err, res) {
          if (err) {
            callback(err);
            return;
          }
          if (res.rowCount === 0) {
            // xt.ext doesn't exist, because this is probably a brand-new DB.
            // No problem! Give them the core extensions.
            adaptExtensions(null, { rows: defaultExtensions });
          } else {
            dataSource.query(extSql, credsClone, adaptExtensions);
          }
        });
      },
      buildAll = function (specs, creds, buildAllCallback) {
        async.series([
          function (done) {
            // step 1: npm install extension if necessary
            // an alternate approach would be only npm install these
            // extensions on an npm install.
            var allExtensions = _.reduce(specs, function (memo, spec) {
              memo.push(spec.extensions);
              return _.flatten(memo);
            }, []);
            var npmExtensions = _.filter(allExtensions, function (extName) {
              return extName.indexOf("node_modules") >= 0;
            });
            if (npmExtensions.length === 0) {
              done();
              return;
            }
            npm.load(function (err, res) {
              if (err) {
                done(err);
                return;
              }
              npm.on("log", function (message) {
                // log the progress of the installation
                console.log(message);
              });
              async.map(npmExtensions, function (extName, next) {
                npm.commands.install([path.basename(extName)], next);
              }, done);
            });
          },
          function (done) {
            // step 2: build the client
            buildClient(specs, done);
          },
          function (done) {
            // step 3: build the database
            buildDatabase.buildDatabase(specs, creds, function (databaseErr, databaseRes) {
              if (databaseErr) {
                buildAllCallback(databaseErr);
                return;
              }
              var returnMessage = "\n";
              _.each(specs, function (spec) {
                returnMessage += "Database: " + spec.database + '\nDirectories:\n';
                _.each(spec.extensions, function (ext) {
                  returnMessage += '  ' + ext + '\n';
                });
              });
              done(null, "Build succeeded." + returnMessage);
            });
          }
        ], function (err, results) {
          buildAllCallback(err, results && results[results.length - 1]);
        });
      },
      config;

    // the config path is not relative if it starts with a slash
    if (options.config && options.config.substring(0, 1) === '/') {
      config = require(options.config);
    } else if (options.config) {
      config = require(path.join(process.cwd(), options.config));
    } else {
      config = require(path.join(__dirname, "../../node-datasource/config.js"));
    }
    creds = config.databaseServer;
    creds.encryptionKeyFile = config.datasource.encryptionKeyFile;
    creds.host = creds.hostname; // adapt our lingo to node-postgres lingo
    creds.username = creds.user; // adapt our lingo to orm installer lingo

    if (options.database) {
      // the user has specified a particular database
      databases.push(options.database);
    } else {
      // build all the databases in node-datasource/config.js
      databases = config.datasource.databases;
    }

    if (options.clientOnly && options.databaseOnly) {
      // This request doesn't make any sense.
      callback("Make up your mind.");

    } else if (options.backup && options.source) {
      callback("You can build from backup or from source but not both.");

    } else if (options.initialize &&
        (options.backup || options.source) &&
        options.database &&
        (!options.extension || options.extension === 'foundation-database')) {
      // Initialize the database. This is serious business, and we only do it if
      // the user does all the arguments correctly. It must be on one database only,
      // with no extensions, with the initialize flag, and with a backup file.

      buildSpecs.database = options.database;
      if (options.backup) {
        // the backup path is not relative if it starts with a slash
        buildSpecs.backup = options.backup.substring(0, 1) === '/' ?
          options.backup :
          path.join(process.cwd(), options.backup);
      }
      if (options.source) {
        // the source path is not relative if it starts with a slash
        buildSpecs.source = options.source.substring(0, 1) === '/' ?
          options.source :
          path.join(process.cwd(), options.source);
      }
      buildSpecs.initialize = true;
      buildSpecs.keepSql = options.keepSql;
      buildSpecs.populateData = options.populateData;
      buildSpecs.wipeViews = options.wipeViews;
      buildSpecs.clientOnly = options.clientOnly;
      buildSpecs.databaseOnly = options.databaseOnly;
      // if we initialize with the foundation, that means we want
      // an unmobilized build
      buildSpecs.extensions = options.extension ? [options.extension] : [
        path.join(__dirname, '../../foundation-database'),
        path.join(__dirname, '../../lib/orm'),
        path.join(__dirname, '../../enyo-client'),
        path.join(__dirname, '../../enyo-client/extensions/source/crm'),
        path.join(__dirname, '../../enyo-client/extensions/source/project'),
        path.join(__dirname, '../../enyo-client/extensions/source/sales'),
        path.join(__dirname, '../../enyo-client/extensions/source/billing'),
        path.join(__dirname, '../../enyo-client/extensions/source/purchasing'),
        path.join(__dirname, '../../enyo-client/extensions/source/oauth2')
      ];
      buildAll([buildSpecs], creds, callback);

    } else if (options.initialize || options.backup || options.source) {
      // The user has not been sufficiently serious.
      callback("If you want to initialize the database, you must specifify " +
        " a database, and use no extensions, and use both the init and either the backup or source flags");

    } else if (options.extension) {
      // the user has specified an extension to build or unregister
      // extensions are assumed to be specified relative to the cwd
      buildSpecs = _.map(databases, function (database) {
        // the extension is not relative if it starts with a slash
        var extension = options.extension.substring(0, 1) === '/' ?
          options.extension :
          path.join(process.cwd(), options.extension);
        return {
          database: database,
          frozen: options.frozen,
          keepSql: options.keepSql,
          populateData: options.populateData,
          wipeViews: options.wipeViews,
          clientOnly: options.clientOnly,
          databaseOnly: options.databaseOnly,
          extensions: [extension]
        };
      });

      if (options.unregister) {
        unregister(buildSpecs, creds, callback);
      } else {
        // synchronous build
        buildAll(buildSpecs, creds, callback);
      }
    } else {
      // build all registered extensions for the database
      async.map(databases, getRegisteredExtensions, function (err, results) {
        // asynchronous...
        buildAll(results, creds, callback);
      });
    }
  };
}());

