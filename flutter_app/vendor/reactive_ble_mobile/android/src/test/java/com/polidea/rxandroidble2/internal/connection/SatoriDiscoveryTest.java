package com.polidea.rxandroidble2.internal.connection;

import android.bluetooth.*;
import com.polidea.rxandroidble2.*;
import com.polidea.rxandroidble2.exceptions.BleDisconnectedException;
import com.polidea.rxandroidble2.internal.operations.*;
import com.polidea.rxandroidble2.internal.serialization.ConnectionOperationQueue;
import io.reactivex.*;
import io.reactivex.Observable;
import io.reactivex.observers.TestObserver;
import io.reactivex.schedulers.Schedulers;
import io.reactivex.subjects.PublishSubject;
import org.junit.jupiter.api.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import com.signify.hue.flutterreactiveble.ble.*;
import io.reactivex.subjects.BehaviorSubject;
import android.content.Context;
import java.util.concurrent.atomic.AtomicReference;

class SatoriDiscoveryTest {
    @Test void nativeConnectionBridgePreservesServiceChangedForPausedRecoveryPolicy() {
        RxBleDevice device = mock(RxBleDevice.class);
        when(device.getMacAddress()).thenReturn("test-device");
        when(device.getConnectionState()).thenReturn(RxBleConnection.RxBleConnectionState.DISCONNECTED);
        when(device.observeConnectionStateChanges()).thenReturn(Observable.never());
        when(device.establishConnection(true)).thenReturn(Observable.error(new BleDisconnectedException(
            new IllegalStateException("GATT database changed; reconnect and rediscover"), "test-device", -1)));
        DeviceConnector connector = new DeviceConnector(device,
            new com.signify.hue.flutterreactiveble.utils.Duration(0, TimeUnit.MILLISECONDS),
            update -> kotlin.Unit.INSTANCE, new ConnectionQueue());
        EstablishConnectionResult value = connector.getConnection$reactive_ble_mobile_release().getValue();
        assertTrue(value instanceof EstablishConnectionFailure);
        assertEquals("satoriServiceChanged", ((EstablishConnectionFailure)value).getErrorMessage());
    }

    BluetoothGatt gatt;
    ConnectionOperationQueue queue;
    OperationsProvider provider;
    ServiceDiscoveryManager manager;
    ServiceDiscoveryOperation operation;
    PublishSubject<RxBleDeviceServices> result;

    @BeforeEach void setup() {
        gatt = mock(BluetoothGatt.class);
        queue = mock(ConnectionOperationQueue.class);
        provider = mock(OperationsProvider.class);
        operation = mock(ServiceDiscoveryOperation.class);
        result = PublishSubject.create();
        when(gatt.getServices()).thenReturn(Collections.singletonList(mock(BluetoothGattService.class)));
        when(provider.provideServiceDiscoveryOperation(anyLong(), any())).thenReturn(operation);
        when(queue.queue(operation)).thenAnswer(invocation -> result);
        manager = new ServiceDiscoveryManager(queue, gatt, provider);
    }

    @Test void nonemptySystemTableStillRequiresNativeDiscovery() {
        TestObserver<RxBleDeviceServices> pending = manager.getDiscoverServicesSingle(7, TimeUnit.SECONDS).test();
        pending.assertNoValues();
        verify(queue).queue(operation);
        verify(gatt, never()).getServices();
        RxBleDeviceServices fresh = mock(RxBleDeviceServices.class);
        result.onNext(fresh);
        pending.assertResult(fresh);
        manager.getDiscoverServicesSingle(20, TimeUnit.SECONDS).test().assertResult(fresh);
        verify(queue, times(1)).queue(operation);
    }

    @Test void repeatedFreshRequestsSharePendingOperationAndReplaceCompletedTable() {
        TestObserver<RxBleDeviceServices> first = manager.discoverFresh(7, TimeUnit.SECONDS).test();
        TestObserver<RxBleDeviceServices> repeated = manager.discoverFresh(7, TimeUnit.SECONDS).test();
        verify(queue, times(1)).queue(operation);
        RxBleDeviceServices old = mock(RxBleDeviceServices.class);
        result.onNext(old);
        first.assertResult(old); repeated.assertResult(old);
        result = PublishSubject.create();
        TestObserver<RxBleDeviceServices> replacement = manager.discoverFresh(7, TimeUnit.SECONDS).test();
        TestObserver<RxBleDeviceServices> ioResolution = manager.getDiscoverServicesSingle(20, TimeUnit.SECONDS).test();
        replacement.assertNoValues(); ioResolution.assertNoValues();
        RxBleDeviceServices fresh = mock(RxBleDeviceServices.class);
        result.onNext(fresh);
        replacement.assertResult(fresh); ioResolution.assertResult(fresh);
        verify(queue, times(2)).queue(operation);
    }

    @Test void lateErrorCannotResetAReplacedGeneration() {
        PublishSubject<RxBleDeviceServices> oldResult = result;
        TestObserver<RxBleDeviceServices> old = manager.discoverFresh(7, TimeUnit.SECONDS).test();
        manager.reset();
        result = PublishSubject.create();
        TestObserver<RxBleDeviceServices> current = manager.discoverFresh(7, TimeUnit.SECONDS).test();
        RxBleDeviceServices fresh = mock(RxBleDeviceServices.class);
        result.onNext(fresh);
        oldResult.onError(new IllegalStateException("old"));
        old.assertError(IllegalStateException.class);
        current.assertResult(fresh);
        manager.getDiscoverServicesSingle(20, TimeUnit.SECONDS).test().assertResult(fresh);
        verify(queue, times(2)).queue(operation);
    }

    @Test void lateSuccessCannotPublishOverNewConnectionTable() {
        PublishSubject<RxBleDeviceServices> oldResult = result;
        manager.discoverFresh(7, TimeUnit.SECONDS).test();
        manager.reset(); result = PublishSubject.create();
        manager.discoverFresh(7, TimeUnit.SECONDS).test();
        RxBleDeviceServices fresh = mock(RxBleDeviceServices.class);
        result.onNext(fresh);
        oldResult.onNext(mock(RxBleDeviceServices.class));
        manager.getDiscoverServicesSingle(20, TimeUnit.SECONDS).test().assertResult(fresh);
    }

    @Test void freshTableFeedsPluginReadWriteAndNotificationResolution() {
        RxBleConnectionImpl connection = new RxBleConnectionImpl(queue, mock(RxBleGattCallback.class), gatt, manager,
                mock(NotificationAndIndicationManager.class), mock(MtuProvider.class), mock(DescriptorWriter.class),
                provider, null, Schedulers.trampoline(), mock(IllegalOperationChecker.class));
        UUID uuid = UUID.fromString("4d89f6a0-73b9-4f14-9d3e-63b2145a0008");
        BluetoothGattCharacteristic characteristic = mock(BluetoothGattCharacteristic.class);
        BluetoothGattService service = mock(BluetoothGattService.class);
        when(characteristic.getUuid()).thenReturn(uuid);
        when(characteristic.getInstanceId()).thenReturn(8);
        when(service.getCharacteristics()).thenReturn(Collections.singletonList(characteristic));
        RxBleDeviceServices fresh = new RxBleDeviceServices(Collections.singletonList(service));
        TestObserver<RxBleDeviceServices> pending = connection.discoverServicesFresh(7, TimeUnit.SECONDS).test();
        result.onNext(fresh); pending.assertResult(fresh);
        // This is the actual shared plugin resolver called by read, both writes,
        // and notification/indication setup, not a display-only lookup.
        for (int path = 0; path < 4; path++) {
            com.signify.hue.flutterreactiveble.ble.extensions.RxBleConnectionExtensionKt
                .resolveCharacteristic(connection, uuid, 8).test().assertResult(characteristic);
        }
        verify(queue, times(1)).queue(operation);
    }

    @Test void serviceChangedTerminatesConnectionSoSubscriptionsCannotUseOldHandles() {
        DisconnectionRouter router = mock(DisconnectionRouter.class);
        BluetoothDevice device = mock(BluetoothDevice.class);
        when(gatt.getDevice()).thenReturn(device);
        when(device.getAddress()).thenReturn("00:00:00:00:00:00");
        RxBleGattCallback callbacks = new RxBleGattCallback(Schedulers.trampoline(),
                mock(BluetoothGattProvider.class), router, mock(NativeCallbackDispatcher.class));
        SatoriGattDiscoveryEvidence.start(gatt);
        callbacks.getBluetoothGattCallback().onServiceChanged(gatt);
        verify(router).onDisconnectedException(any(BleDisconnectedException.class));
        assertEquals("serviceChanged", SatoriGattDiscoveryEvidence.snapshot(gatt).get("failure"));
    }

    @Test void timedOutDiscoveryTerminatesGattSoLateCallbacksCannotSatisfyANewOperation() {
        DisconnectionRouter router = mock(DisconnectionRouter.class);
        BluetoothDevice device = mock(BluetoothDevice.class);
        when(gatt.getDevice()).thenReturn(device);
        when(device.getAddress()).thenReturn("00:00:00:00:00:00");
        RxBleGattCallback callbacks = new RxBleGattCallback(Schedulers.trampoline(),
            mock(BluetoothGattProvider.class), router, mock(NativeCallbackDispatcher.class));
        callbacks.abortTimedOutDiscovery(gatt);
        verify(router).onDisconnectedException(any(BleDisconnectedException.class));
    }

    @Test void productionClientDiscoversOneToNineDespiteCachedOneToFiveAndUsesNewHandlesForAllIo() {
        runProductionDiscovery(true);
    }

    @Test void publicDiscoverySuccessCanStillReturnOneToFiveWhenTheOsKeepsItsCache() {
        runProductionDiscovery(false);
    }

    private void runProductionDiscovery(boolean osReturnsFreshTable) {
        // Only the OS/radio and scheduling boundary are test doubles. The plugin
        // client, Rx connection, manager, operation and callback are production classes.
        List<BluetoothGattCharacteristic> oldChars = chars(5, 100);
        List<BluetoothGattCharacteristic> newChars = chars(9, 200);
        BluetoothGattService oldService = mock(BluetoothGattService.class);
        BluetoothGattService newService = mock(BluetoothGattService.class);
        when(oldService.getCharacteristics()).thenReturn(oldChars);
        when(newService.getCharacteristics()).thenReturn(newChars);
        AtomicReference<List<BluetoothGattService>> osTable = new AtomicReference<>(Collections.singletonList(oldService));
        when(gatt.getServices()).thenAnswer(inv -> osTable.get());
        when(gatt.discoverServices()).thenReturn(true);
        BluetoothDevice bondedDevice = mock(BluetoothDevice.class);
        when(gatt.getDevice()).thenReturn(bondedDevice);
        when(bondedDevice.getAddress()).thenReturn("00:00:00:00:00:00");
        when(bondedDevice.getBondState()).thenReturn(BluetoothDevice.BOND_BONDED);
        DisconnectionRouter router = mock(DisconnectionRouter.class);
        when(router.asErrorOnlyObservable()).thenReturn(Observable.never());
        RxBleGattCallback callbacks = new RxBleGattCallback(Schedulers.trampoline(),
            mock(BluetoothGattProvider.class), router, mock(NativeCallbackDispatcher.class));
        ServiceDiscoveryOperation discovery = SatoriOperationFactory.discovery(callbacks, gatt, new io.reactivex.schedulers.TestScheduler());
        when(provider.provideServiceDiscoveryOperation(anyLong(), any())).thenReturn(discovery);
        when(queue.queue(discovery)).thenAnswer(inv -> discovery.run(mock(com.polidea.rxandroidble2.internal.serialization.QueueReleaseInterface.class)));
        IllegalOperationChecker checker = mock(IllegalOperationChecker.class);
        when(checker.checkAnyPropertyMatches(any(), anyInt())).thenReturn(Completable.complete());
        NotificationAndIndicationManager notifications = mock(NotificationAndIndicationManager.class);
        when(notifications.setupServerInitiatedCharacteristicRead(any(), any(), anyBoolean()))
            .thenReturn(Observable.just(Observable.just(new byte[]{9})));
        RxBleConnectionImpl connection = new RxBleConnectionImpl(queue, callbacks, gatt, manager,
            notifications, mock(MtuProvider.class), mock(DescriptorWriter.class), provider, null,
            Schedulers.trampoline(), checker);
        RxBleDevice bleDevice = mock(RxBleDevice.class);
        when(bleDevice.getBluetoothDevice()).thenReturn(bondedDevice);
        RxBleClient bleClient = mock(RxBleClient.class);
        when(bleClient.getBleDevice("test-device")).thenReturn(bleDevice);
        ReactiveBleClient.Companion.setRxBleClient$reactive_ble_mobile_release(bleClient);
        BehaviorSubject<EstablishConnectionResult> connected = BehaviorSubject.createDefault(new EstablishedConnection("test-device", connection));
        DeviceConnector connector = mock(DeviceConnector.class);
        when(connector.getConnection$reactive_ble_mobile_release()).thenReturn(connected);
        Map<String, DeviceConnector> active = new HashMap<>(); active.put("test-device", connector);
        ReactiveBleClient.Companion.setActiveConnections$reactive_ble_mobile_release(active);
        ReactiveBleClient client = new ReactiveBleClient(mock(Context.class));

        TestObserver<RxBleDeviceServices> failed = client.discoverServices("test-device").test();
        callbacks.getBluetoothGattCallback().onServicesDiscovered(gatt, 133);
        failed.assertError(com.polidea.rxandroidble2.exceptions.BleGattException.class).assertNoValues();
        assertEquals("failed", client.getGattDiscoveryEvidence("test-device").blockingGet().get("phase"));
        assertEquals(133, client.getGattDiscoveryEvidence("test-device").blockingGet().get("status"));
        // A reported failure cannot turn the still-present old 1-5 table into
        // a discovered result. Start the independent successful attempt below.
        clearInvocations(gatt);
        TestObserver<RxBleDeviceServices> fresh = client.discoverServices("test-device").test();
        TestObserver<RxBleDeviceServices> repeated = client.discoverServices("test-device").test();
        fresh.assertNoValues(); repeated.assertNoValues();
        verify(gatt, times(1)).discoverServices();
        verify(gatt, never()).getServices();
        assertEquals("started", client.getGattDiscoveryEvidence("test-device").blockingGet().get("phase"));
        // Unlike the earlier happy path, keep the OS cache on the failure
        // reproduction. The native public call and its real success callback
        // still execute, but the server's new table is not returned by the OS.
        if (osReturnsFreshTable) osTable.set(Collections.singletonList(newService));
        callbacks.getBluetoothGattCallback().onServicesDiscovered(gatt, BluetoothGatt.GATT_SUCCESS);
        fresh.assertValue(table -> table.getBluetoothGattServices().get(0).getCharacteristics().size() == (osReturnsFreshTable ? 9 : 5));
        repeated.assertValueCount(1);
        assertEquals(true, client.getGattDiscoveryEvidence("test-device").blockingGet().get("callbackReceived"));
        assertEquals("completed", client.getGattDiscoveryEvidence("test-device").blockingGet().get("phase"));
        assertEquals(osReturnsFreshTable ? 9 : 5, client.getDiscoveredServices("test-device").blockingGet().getBluetoothGattServices().get(0).getCharacteristics().size());

        if (!osReturnsFreshTable) {
            for (int index : new int[]{5, 6, 7, 8}) {
                BluetoothGattCharacteristic missing = newChars.get(index);
                client.readCharacteristic("test-device", missing.getUuid(), missing.getInstanceId()).test()
                    .assertError(java.util.NoSuchElementException.class).assertNoValues();
            }
            verify(provider, never()).provideReadCharacteristic(any());
            // Another explicit public discovery is also allowed to succeed
            // with the same OS cache. It is not a cache-eviction guarantee.
            TestObserver<RxBleDeviceServices> again = client.discoverServices("test-device").test();
            again.assertNoValues();
            callbacks.getBluetoothGattCallback().onServicesDiscovered(gatt, BluetoothGatt.GATT_SUCCESS);
            again.assertValue(table -> table.getBluetoothGattServices().get(0).getCharacteristics().size() == 5);
            verify(gatt, times(2)).discoverServices();
            verify(bondedDevice, never()).createBond();
            return;
        }

        CharacteristicReadOperation read = mock(CharacteristicReadOperation.class);
        when(provider.provideReadCharacteristic(any())).thenReturn(read);
        when(queue.queue(read)).thenReturn(Observable.just(new byte[]{1}));
        CharacteristicWriteOperation write = mock(CharacteristicWriteOperation.class);
        when(provider.provideWriteCharacteristic(any(), any())).thenReturn(write);
        when(queue.queue(write)).thenReturn(Observable.just(new byte[]{2}));
        for (int index : new int[]{5, 7, 8}) {
            BluetoothGattCharacteristic c = newChars.get(index);
            client.readCharacteristic("test-device", c.getUuid(), c.getInstanceId()).test()
                .assertValue(value -> value instanceof CharOperationSuccessful);
            verify(provider).provideReadCharacteristic(c);
        }
        BluetoothGattCharacteristic c = newChars.get(7);
        client.writeCharacteristicWithResponse("test-device", c.getUuid(), c.getInstanceId(), new byte[]{2}).test()
            .assertValue(value -> value instanceof CharOperationSuccessful);
        client.writeCharacteristicWithoutResponse("test-device", c.getUuid(), c.getInstanceId(), new byte[]{2}).test()
            .assertValue(value -> value instanceof CharOperationSuccessful);
        verify(provider, times(2)).provideWriteCharacteristic(eq(c), any());
        client.setupNotification("test-device", c.getUuid(), c.getInstanceId()).test().assertValueCount(1);
        verify(notifications).setupServerInitiatedCharacteristicRead(c, NotificationSetupMode.COMPAT, false);
        verify(gatt, times(1)).discoverServices();
        for (BluetoothGattCharacteristic old : oldChars) {
            verify(provider, never()).provideReadCharacteristic(old);
            verify(provider, never()).provideWriteCharacteristic(eq(old), any());
        }
        // Simulate the radio's connection termination when the real production
        // Service Changed callback asks its router to invalidate the connection.
        doAnswer(inv -> { connected.onNext(new EstablishConnectionFailure("test-device", "serviceChanged")); return null; })
            .when(router).onDisconnectedException(any(BleDisconnectedException.class));
        callbacks.getBluetoothGattCallback().onServiceChanged(gatt);
        client.readCharacteristic("test-device", c.getUuid(), c.getInstanceId()).test()
            .assertValue(value -> value instanceof CharOperationFailed);
        assertEquals(BluetoothDevice.BOND_BONDED, bondedDevice.getBondState());
        verify(bondedDevice, never()).createBond();
        verify(connector, never()).clearGattCache$reactive_ble_mobile_release();
    }

    private static List<BluetoothGattCharacteristic> chars(int count, int handleBase) {
        List<BluetoothGattCharacteristic> chars = new ArrayList<>();
        for (int i = 1; i <= count; i++) {
            BluetoothGattCharacteristic c = mock(BluetoothGattCharacteristic.class);
            when(c.getUuid()).thenReturn(UUID.fromString(String.format("4d89f6a0-73b9-4f14-9d3e-63b2145a%04d", i)));
            when(c.getInstanceId()).thenReturn(handleBase + i);
            when(c.getDescriptors()).thenReturn(Collections.emptyList());
            when(c.getProperties()).thenReturn(BluetoothGattCharacteristic.PROPERTY_NOTIFY | BluetoothGattCharacteristic.PROPERTY_READ | BluetoothGattCharacteristic.PROPERTY_WRITE);
            chars.add(c);
        }
        return chars;
    }
}
