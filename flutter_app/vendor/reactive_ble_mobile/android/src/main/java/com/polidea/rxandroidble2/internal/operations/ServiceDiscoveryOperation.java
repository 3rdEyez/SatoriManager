package com.polidea.rxandroidble2.internal.operations;

import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattService;
import androidx.annotation.NonNull;

import com.polidea.rxandroidble2.RxBleDeviceServices;
import com.polidea.rxandroidble2.exceptions.BleGattCallbackTimeoutException;
import com.polidea.rxandroidble2.exceptions.BleGattOperationType;
import com.polidea.rxandroidble2.internal.SingleResponseOperation;
import com.polidea.rxandroidble2.internal.connection.RxBleGattCallback;
import com.polidea.rxandroidble2.internal.logger.LoggerUtilBluetoothServices;

import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import io.reactivex.Scheduler;
import io.reactivex.Single;
import io.reactivex.functions.Function;

public class ServiceDiscoveryOperation extends SingleResponseOperation<RxBleDeviceServices> {

    final BluetoothGatt bluetoothGatt;
    final LoggerUtilBluetoothServices bleServicesLogger;

    ServiceDiscoveryOperation(
            RxBleGattCallback rxBleGattCallback,
            BluetoothGatt bluetoothGatt,
            LoggerUtilBluetoothServices bleServicesLogger,
            TimeoutConfiguration timeoutConfiguration) {
        super(bluetoothGatt, rxBleGattCallback, BleGattOperationType.SERVICE_DISCOVERY, timeoutConfiguration);
        this.bluetoothGatt = bluetoothGatt;
        this.bleServicesLogger = bleServicesLogger;
    }

    @Override
    protected Single<RxBleDeviceServices> getCallback(RxBleGattCallback rxBleGattCallback) {
        return rxBleGattCallback.getOnServicesDiscovered().firstOrError()
                .doOnSuccess(rxBleDeviceServices ->
                        bleServicesLogger.log(rxBleDeviceServices, bluetoothGatt.getDevice()));
    }

    @Override
    protected boolean startOperation(BluetoothGatt bluetoothGatt) {
        com.polidea.rxandroidble2.internal.connection.SatoriGattDiscoveryEvidence.start(bluetoothGatt);
        boolean accepted = bluetoothGatt.discoverServices();
        com.polidea.rxandroidble2.internal.connection.SatoriGattDiscoveryEvidence.accepted(bluetoothGatt, accepted);
        return accepted;
    }

    /** A missing completion callback is a failure, even if Android still
     * exposes a nonempty previous table. Close this connection to isolate late
     * callbacks from the next discovery. */
    @NonNull
    @Override
    protected Single<RxBleDeviceServices> timeoutFallbackProcedure(
            final BluetoothGatt bluetoothGatt,
            final RxBleGattCallback rxBleGattCallback,
            final Scheduler timeoutScheduler
    ) {
        return Single.defer(() -> {
            com.polidea.rxandroidble2.internal.connection.SatoriGattDiscoveryEvidence.fail(bluetoothGatt, "timeout");
            rxBleGattCallback.abortTimedOutDiscovery(bluetoothGatt);
            return Single.error(new BleGattCallbackTimeoutException(bluetoothGatt, BleGattOperationType.SERVICE_DISCOVERY));
        });
    }

    @Override
    public String toString() {
        return "ServiceDiscoveryOperation{" + super.toString() + '}';
    }
}
