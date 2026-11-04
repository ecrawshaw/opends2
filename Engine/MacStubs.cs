using System;

namespace EdiabasLib
{
    // EdInterfaceObd hooks Bluetooth adapters by port name. The real class uses Windows-only Bluetooth
    // APIs, so on the Mac every call fails and a "BLUETOOTH:" port simply can't connect. The K+DCAN
    // cable is a serial port and never goes through here.
    public static class EdBluetoothInterface
    {
        public const string PortId = "BLUETOOTH";
        public static EdiabasNet Ediabas { get; set; }

        public static bool InterfaceConnect(string port, object parameter) => false;
        public static bool InterfaceDisconnect() => true;
        public static bool InterfaceTransmitCancel(bool cancel) => false;
        public static EdInterfaceObd.InterfaceErrorResult InterfaceSetConfig(EdInterfaceObd.Protocol protocol, int baudRate, int dataBits, EdInterfaceObd.SerialParity parity, bool allowBitBang) =>
            EdInterfaceObd.InterfaceErrorResult.ConfigError;
        public static bool InterfaceSetDtr(bool dtr) => false;
        public static bool InterfaceSetRts(bool rts) => false;
        public static bool InterfaceGetDsr(out bool dsr) { dsr = false; return false; }
        public static bool InterfaceSetBreak(bool enable) => false;
        public static bool InterfaceSetInterByteTime(int time) => false;
        public static bool InterfaceSetCanIds(int canTxId, int canRxId, EdInterfaceObd.CanFlags canFlags) => false;
        public static bool InterfacePurgeInBuffer() => false;
        public static bool InterfaceAdapterEcho() => false;
        public static bool InterfaceHasPreciseTimeout() => false;
        public static bool InterfaceHasAutoBaudRate() => false;
        public static bool InterfaceHasAutoKwp1281() => false;
        public static int? InterfaceAdapterVersion() => null;
        public static byte[] InterfaceAdapterSerial() => null;
        public static double? InterfaceAdapterVoltage() => null;
        public static bool InterfaceHasIgnitionStatus() => false;
        public static bool InterfaceSendData(byte[] sendData, int length, bool setDtr, double dtrTimeCorr) => false;
        public static bool InterfaceReceiveData(byte[] receiveData, int offset, int length, int timeout, int timeoutTelEnd, EdiabasNet ediabasLog) => false;
        public static bool InterfaceSendPulse(UInt64 dataBits, int length, int pulseWidth, bool setDtr, bool bothLines, int autoKeyByteDelay) => false;
    }
}
