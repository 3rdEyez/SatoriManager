"""Run the native discovery regression tests against the actual Gradle output.

No device, Bluetooth adapter, emulator, network or private key is accessed.
Test dependencies must already exist in --test-libs.
"""
import argparse
from pathlib import Path
import subprocess

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--java-home', type=Path, required=True)
    p.add_argument('--android-jar', type=Path, required=True)
    p.add_argument('--gradle-cache', type=Path, required=True)
    p.add_argument('--test-libs', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    app = Path(__file__).resolve().parents[1] / 'flutter_app'
    cp = [app / 'build/reactive_ble_mobile/intermediates/javac/release/compileReleaseJavaWithJavac/classes',
          app / 'build/reactive_ble_mobile/tmp/kotlin-classes/release',
          app / 'build/reactive_ble_mobile/satori-rx/rxandroidble-1.16.0-base.jar', args.android_jar]
    groups = ['io.reactivex.rxjava2', 'com.jakewharton.rxrelay2',
              'com.polidea.rxandroidble2/dagger-library-shadow', 'org.reactivestreams', 'androidx.annotation',
              'org.jetbrains.kotlin/kotlin-stdlib', 'org.jetbrains.kotlin/kotlin-stdlib-jdk7',
              'org.jetbrains.kotlin/kotlin-stdlib-jdk8']
    for group in groups:
        cp.extend(sorted((args.gradle_cache / group).rglob('*.jar')))
    cp.extend(sorted(args.test_libs.glob('*.jar')))
    classpath = ':'.join(map(str, cp))
    args.output.mkdir(parents=True, exist_ok=True)
    sources = sorted((app / 'vendor/reactive_ble_mobile/android/src/test/java').rglob('*.java'))
    subprocess.run([str(args.java_home / 'bin/javac'), '-cp', classpath, '-d', str(args.output),
                    *map(str, sources)], check=True)
    command = [str(args.java_home / 'bin/java'),
               '-javaagent:' + str(args.test_libs / 'byte-buddy-agent-1.15.4.jar'),
               '-cp', str(args.output) + ':' + classpath, 'org.junit.platform.console.ConsoleLauncher',
               'execute', '--select-class', 'com.polidea.rxandroidble2.internal.connection.SatoriDiscoveryTest',
               '--select-class', 'com.polidea.rxandroidble2.internal.operations.SatoriNativeOperationTest',
               '--disable-banner', '--details=summary']
    subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
