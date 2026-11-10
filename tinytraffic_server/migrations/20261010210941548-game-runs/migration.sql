BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "game_run" (
    "id" bigserial PRIMARY KEY,
    "authUserId" uuid NOT NULL,
    "seed" bigint NOT NULL,
    "simVersion" bigint NOT NULL,
    "startedAt" timestamp without time zone NOT NULL,
    "finishedAt" timestamp without time zone,
    "status" text NOT NULL,
    "score" bigint,
    "ticks" bigint,
    "rejectReason" text
);

-- Indexes
CREATE INDEX "game_run_user_idx" ON "game_run" USING btree ("authUserId", "startedAt");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "player_stats" (
    "id" bigserial PRIMARY KEY,
    "authUserId" uuid NOT NULL,
    "nickname" text NOT NULL,
    "bestScore" bigint NOT NULL,
    "bestRunId" bigint,
    "bestAt" timestamp without time zone,
    "totalRuns" bigint NOT NULL,
    "totalCoins" bigint NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "player_stats_user_idx" ON "player_stats" USING btree ("authUserId");
CREATE INDEX "player_stats_best_idx" ON "player_stats" USING btree ("bestScore");


--
-- MIGRATION VERSION FOR tinytraffic
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('tinytraffic', '20261010210941548-game-runs', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261010210941548-game-runs', "timestamp" = now();

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
