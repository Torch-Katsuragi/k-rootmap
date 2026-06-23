// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License v2 or later.
// See the LICENSE file at the repository root for details.

// k-rootmap パーティ位置共有のメンテナンス用 Cloud Functions。
//
// 目的: 失効・終了したルームを定期削除し、RTDBのstorage肥大とコストを抑える
// （設計: docs/technical/location-sharing.md §8 コスト/クリーンアップ）。

const {onSchedule} = require("firebase-functions/v2/scheduler");
const {logger} = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * 失効/終了ルームの定期purge。
 * - meta.active === false（hostが終了した）
 * - meta.expiresAt < now（失効した）
 * のいずれかに該当するルームをまとめて削除する。
 */
exports.purgeExpiredRooms = onSchedule(
    {
      schedule: "every 24 hours",
      timeZone: "Asia/Tokyo",
      region: "asia-southeast1",
    },
    async () => {
      const now = Date.now();
      const db = admin.database();
      const snap = await db.ref("rooms").get();
      if (!snap.exists()) {
        logger.info("rooms なし、purge対象なし");
        return;
      }

      const updates = {};
      snap.forEach((room) => {
        const meta = room.child("meta");
        const active = meta.child("active").val();
        const expiresAt = meta.child("expiresAt").val() || 0;
        if (active === false || expiresAt < now) {
          updates[room.key] = null; // null書込みで削除
        }
      });

      const count = Object.keys(updates).length;
      if (count > 0) {
        await db.ref("rooms").update(updates);
      }
      logger.info(`purgeExpiredRooms: ${count} 件のルームを削除`);
    },
);
