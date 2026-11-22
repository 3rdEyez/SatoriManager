package com.polidea.rxandroidble2.internal.connection;


import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattService;
import androidx.annotation.NonNull;

import com.polidea.rxandroidble2.RxBleDeviceServices;
import com.polidea.rxandroidble2.internal.operations.OperationsProvider;
import com.polidea.rxandroidble2.internal.operations.ServiceDiscoveryOperation;
import com.polidea.rxandroidble2.internal.operations.TimeoutConfiguration;
import com.polidea.rxandroidble2.internal.serialization.ConnectionOperationQueue;

import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.TimeUnit;

import bleshadow.javax.inject.Inject;
import io.reactivex.Maybe;
import io.reactivex.Single;
import io.reactivex.disposables.Disposable;
import io.reactivex.functions.Action;
import io.reactivex.functions.Consumer;
import io.reactivex.functions.Function;
import io.reactivex.functions.Predicate;
import io.reactivex.internal.functions.Functions;
import io.reactivex.schedulers.Schedulers;
import io.reactivex.subjects.BehaviorSubject;
import io.reactivex.subjects.Subject;

@ConnectionScope
class ServiceDiscoveryManager {

    final ConnectionOperationQueue operationQueue;
    final BluetoothGatt bluetoothGatt;
    final OperationsProvider operationProvider;
    private Single<RxBleDeviceServices> deviceServicesObservable;
    final Subject<TimeoutConfiguration> timeoutBehaviorSubject = BehaviorSubject.<TimeoutConfiguration>create().toSerialized();
    volatile boolean hasCachedResults = false;
    private boolean discoveryInFlight = false;
    private long generation = 0;

    @Inject
    ServiceDiscoveryManager(ConnectionOperationQueue operationQueue, BluetoothGatt bluetoothGatt, OperationsProvider operationProvider) {
        this.operationQueue = operationQueue;
        this.bluetoothGatt = bluetoothGatt;
        this.operationProvider = operationProvider;
        reset();
    }

    synchronized Single<RxBleDeviceServices> getDiscoverServicesSingle(final long timeout, final TimeUnit timeoutTimeUnit) {
        if (hasCachedResults) {
            // optimisation to decrease the number of allocations
            return deviceServicesObservable;
        } else {
            return deviceServicesObservable.doOnSubscribe(
                    new Consumer<Disposable>() {
                        @Override
                        public void accept(Disposable disposable) {
                            timeoutBehaviorSubject.onNext(new TimeoutConfiguration(timeout, timeoutTimeUnit, Schedulers.computation()));
                        }
                    });
        }
    }

    synchronized Single<RxBleDeviceServices> discoverFresh(long timeout, TimeUnit unit) {
        // Repeated taps share the same pending native operation. A completed table
        // is replaced before any future UUID resolution can use it.
        if (!discoveryInFlight) reset();
        discoveryInFlight = true;
        return getDiscoverServicesSingle(timeout, unit);
    }

    synchronized void reset() {
        hasCachedResults = false;
        discoveryInFlight = false;
        final long currentGeneration = ++generation;
        this.deviceServicesObservable = getTimeoutConfiguration().flatMap(scheduleActualDiscoveryWithTimeout())
                .doOnSubscribe(disposable -> { synchronized (ServiceDiscoveryManager.this) {
                    if (currentGeneration == generation) discoveryInFlight = true;
                } })
                .doOnSuccess(Functions.actionConsumer(new Action() {
                    @Override
                    public void run() {
                        synchronized (ServiceDiscoveryManager.this) {
                            if (currentGeneration == generation) {
                                hasCachedResults = true;
                                discoveryInFlight = false;
                            }
                        }
                    }
                }))
                .doOnError(Functions.actionConsumer(new Action() {
                    @Override
                    public void run() {
                        synchronized (ServiceDiscoveryManager.this) {
                            if (currentGeneration == generation) reset();
                        }
                    }
                }))
                .cache();
    }

    @NonNull
    private Single<TimeoutConfiguration> getTimeoutConfiguration() {
        return timeoutBehaviorSubject.firstOrError();
    }

    @NonNull
    private Function<TimeoutConfiguration, Single<RxBleDeviceServices>> scheduleActualDiscoveryWithTimeout() {
        return new Function<TimeoutConfiguration, Single<RxBleDeviceServices>>() {
            @Override
            public Single<RxBleDeviceServices> apply(TimeoutConfiguration timeoutConf) {
                final ServiceDiscoveryOperation operation = operationProvider
                        .provideServiceDiscoveryOperation(timeoutConf.timeout, timeoutConf.timeoutTimeUnit);
                return operationQueue.queue(operation)
                        .firstOrError();
            }
        };
    }
}
