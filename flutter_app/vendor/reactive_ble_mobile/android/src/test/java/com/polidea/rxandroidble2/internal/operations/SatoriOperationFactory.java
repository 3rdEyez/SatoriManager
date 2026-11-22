package com.polidea.rxandroidble2.internal.operations;
import android.bluetooth.BluetoothGatt;
import com.polidea.rxandroidble2.internal.connection.RxBleGattCallback;
import com.polidea.rxandroidble2.internal.logger.LoggerUtilBluetoothServices;
import io.reactivex.Scheduler;
import java.util.concurrent.TimeUnit;
import static org.mockito.Mockito.mock;

/** Exposes the package-scoped production constructor only to JVM tests. */
public final class SatoriOperationFactory {
    public static ServiceDiscoveryOperation discovery(RxBleGattCallback callback, BluetoothGatt gatt, Scheduler clock) {
        return new ServiceDiscoveryOperation(callback, gatt, mock(LoggerUtilBluetoothServices.class),
            new TimeoutConfiguration(7, TimeUnit.SECONDS, clock));
    }
}
