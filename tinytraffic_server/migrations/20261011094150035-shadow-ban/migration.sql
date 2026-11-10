BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "game_run" ADD COLUMN "unverifiable" boolean NOT NULL DEFAULT false;
--
-- ACTION ALTER TABLE
--
ALTER TABLE "player_stats" ADD COLUMN "shadowBanned" boolean NOT NULL DEFAULT false;
ALTER TABLE "player_stats" ADD COLUMN "banReason" text;
ALTER TABLE "player_stats" ADD COLUMN "bannedAt" timestamp without time zone;

--
-- MIGRATION VERSION FOR tinytraffic
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('tinytraffic', '20261011094150035-shadow-ban', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261011094150035-shadow-ban', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260824182259319', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260824182259319', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod_auth_idp
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod_auth_idp', '20260924105404509', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260924105404509', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod_auth_core
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod_auth_core', '20260924105232991', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260924105232991', "timestamp" = now();


COMMIT;
