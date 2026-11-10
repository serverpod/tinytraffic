BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "score_count" (
    "id" bigserial PRIMARY KEY,
    "score" bigint NOT NULL,
    "players" bigint NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "score_count_score_idx" ON "score_count" USING btree ("score");


--
-- MIGRATION VERSION FOR tinytraffic
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('tinytraffic', '20261022065823547', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261022065823547', "timestamp" = now();

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
