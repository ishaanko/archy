// Minimal Web Serial typings (Chrome/Edge), just what serial.ts uses.
interface SerialPortRequestOptions {
  filters?: { usbVendorId?: number; usbProductId?: number }[]
}
interface SerialOptions {
  baudRate: number
}
interface SerialPort {
  readonly readable: ReadableStream<Uint8Array<ArrayBuffer>> | null
  readonly writable: WritableStream<Uint8Array<ArrayBuffer>> | null
  open(options: SerialOptions): Promise<void>
  close(): Promise<void>
}
interface Serial {
  requestPort(options?: SerialPortRequestOptions): Promise<SerialPort>
}
interface Navigator {
  readonly serial?: Serial
}
