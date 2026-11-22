package com.polidea.rxandroidble2.internal.connection;

import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattService;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.WeakHashMap;
import java.util.concurrent.atomic.AtomicLong;

/** Local UUID-only evidence; never contains addresses or attribute values. */
public final class SatoriGattDiscoveryEvidence {
    private static final Map<BluetoothGatt, Map<String, Object>> records = new WeakHashMap<>();
    private static final AtomicLong sequence = new AtomicLong();

    public static synchronized void start(BluetoothGatt gatt) {
        Map<String, Object> record = new LinkedHashMap<>();
        record.put("operation", sequence.incrementAndGet());
        record.put("source", "androidPublicDiscoverServices");
        record.put("phase", "started");
        record.put("startedAtMs", System.currentTimeMillis());
        record.put("callbackReceived", false);
        records.put(gatt, record);
    }

    public static synchronized void accepted(BluetoothGatt gatt, boolean accepted) {
        Map<String, Object> record = records.get(gatt);
        if (record == null) return;
        record.put("accepted", accepted);
        if (!accepted) fail(gatt, "startRejected");
    }

    public static synchronized void callback(BluetoothGatt gatt, int status) {
        Map<String, Object> record = records.get(gatt);
        if (record == null || !"started".equals(record.get("phase"))) return;
        record.put("callbackReceived", true);
        record.put("status", status);
        record.put("completedAtMs", System.currentTimeMillis());
        record.put("phase", status == BluetoothGatt.GATT_SUCCESS ? "completed" : "failed");
    }

    public static synchronized void fail(BluetoothGatt gatt, String reason) {
        Map<String, Object> record = records.get(gatt);
        if (record == null) return;
        record.put("phase", "failed");
        record.put("failure", reason);
        record.put("completedAtMs", System.currentTimeMillis());
    }

    public static synchronized Map<String, Object> snapshot(BluetoothGatt gatt) {
        Map<String, Object> record = records.get(gatt);
        return record == null ? new LinkedHashMap<>() : new LinkedHashMap<>(record);
    }

    private SatoriGattDiscoveryEvidence() {}
}
