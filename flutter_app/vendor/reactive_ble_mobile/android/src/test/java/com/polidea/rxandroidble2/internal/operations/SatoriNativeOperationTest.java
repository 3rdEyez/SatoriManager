package com.polidea.rxandroidble2.internal.operations;

import android.bluetooth.*;
import com.polidea.rxandroidble2.RxBleDeviceServices;
import com.polidea.rxandroidble2.exceptions.*;
import com.polidea.rxandroidble2.internal.connection.*;
import com.polidea.rxandroidble2.internal.logger.LoggerUtilBluetoothServices;
import com.polidea.rxandroidble2.internal.serialization.QueueReleaseInterface;
import io.reactivex.observers.TestObserver;
import io.reactivex.schedulers.TestScheduler;
import io.reactivex.subjects.PublishSubject;
import org.junit.jupiter.api.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import static org.mockito.Mockito.*;
import static org.junit.jupiter.api.Assertions.*;

class SatoriNativeOperationTest {
    BluetoothGatt gatt;
    RxBleGattCallback callback;
    PublishSubject<RxBleDeviceServices> results;
    TestScheduler clock;
    ServiceDiscoveryOperation operation;

    @BeforeEach void setup() {
        gatt = mock(BluetoothGatt.class); callback = mock(RxBleGattCallback.class);
        clock = new TestScheduler(); results = PublishSubject.create();
        when(callback.getOnServicesDiscovered()).thenReturn(results);
        when(gatt.getServices()).thenReturn(Collections.singletonList(mock(BluetoothGattService.class)));
        when(gatt.discoverServices()).thenReturn(true);
        operation = new ServiceDiscoveryOperation(callback, gatt, mock(LoggerUtilBluetoothServices.class),
                new TimeoutConfiguration(7, TimeUnit.SECONDS, clock));
    }

    @Test void publicCallIsAsynchronousAndOnlyCompletesOnActualCallback() {
        TestObserver<RxBleDeviceServices> pending = operation.run(mock(QueueReleaseInterface.class)).test();
        verify(gatt).discoverServices();
        pending.assertNoValues();
        assertEquals(false, SatoriGattDiscoveryEvidence.snapshot(gatt).get("callbackReceived"));
        RxBleDeviceServices fresh = mock(RxBleDeviceServices.class);
        SatoriGattDiscoveryEvidence.callback(gatt, BluetoothGatt.GATT_SUCCESS);
        results.onNext(fresh);
        pending.assertResult(fresh);
        Map<String, Object> evidence = SatoriGattDiscoveryEvidence.snapshot(gatt);
        assertEquals("completed", evidence.get("phase"));
        assertEquals(true, evidence.get("accepted"));
        assertEquals(true, evidence.get("callbackReceived"));
        assertTrue((Long)evidence.get("completedAtMs") >= (Long)evidence.get("startedAtMs"));
    }

    @Test void timeoutRejectsNonemptySystemTableAndLateCallback() {
        TestObserver<RxBleDeviceServices> pending = operation.run(mock(QueueReleaseInterface.class)).test();
        clock.advanceTimeBy(7, TimeUnit.SECONDS);
        pending.assertError(BleGattCallbackTimeoutException.class).assertNoValues();
        verify(callback).abortTimedOutDiscovery(gatt);
        verify(gatt, never()).getServices();
        SatoriGattDiscoveryEvidence.callback(gatt, BluetoothGatt.GATT_SUCCESS);
        results.onNext(mock(RxBleDeviceServices.class));
        pending.assertNoValues();
        assertEquals("failed", SatoriGattDiscoveryEvidence.snapshot(gatt).get("phase"));
        assertEquals(false, SatoriGattDiscoveryEvidence.snapshot(gatt).get("callbackReceived"));
    }

    @Test void rejectedPublicCallIsFailureWithoutUsingOldTable() {
        when(gatt.discoverServices()).thenReturn(false);
        operation.run(mock(QueueReleaseInterface.class)).test().assertError(BleGattCannotStartException.class);
        assertEquals("startRejected", SatoriGattDiscoveryEvidence.snapshot(gatt).get("failure"));
    }

    @Test void evidenceIsScopedToGattConnectionAndContainsNoPrivateValues() {
        operation.startOperation(gatt);
        BluetoothGatt other = mock(BluetoothGatt.class);
        assertTrue(SatoriGattDiscoveryEvidence.snapshot(other).isEmpty());
        assertFalse(SatoriGattDiscoveryEvidence.snapshot(gatt).toString().contains("address"));
    }
}
