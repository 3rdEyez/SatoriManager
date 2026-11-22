package android.bluetooth;

/** JVM-only stand-in for the SDK's throwing callback stub, like AGP's mockable
 * android.jar. It is under src/test and cannot enter the production APK. */
public abstract class BluetoothGattCallback {
    public void onConnectionStateChange(BluetoothGatt gatt, int status, int state) {}
    public void onServicesDiscovered(BluetoothGatt gatt, int status) {}
    public void onServiceChanged(BluetoothGatt gatt) {}
    public void onCharacteristicRead(BluetoothGatt gatt, BluetoothGattCharacteristic c, int status) {}
    public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic c, int status) {}
    public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic c) {}
    public void onDescriptorRead(BluetoothGatt gatt, BluetoothGattDescriptor d, int status) {}
    public void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor d, int status) {}
    public void onReadRemoteRssi(BluetoothGatt gatt, int rssi, int status) {}
    public void onMtuChanged(BluetoothGatt gatt, int mtu, int status) {}
    public void onPhyRead(BluetoothGatt gatt, int tx, int rx, int status) {}
    public void onPhyUpdate(BluetoothGatt gatt, int tx, int rx, int status) {}
}
