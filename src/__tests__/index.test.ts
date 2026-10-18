import * as Nslookup from "..";
import ExpoNslookupModule from "../ExpoNslookupModule";

jest.mock("../ExpoNslookupModule", () => ({
  __esModule: true,
  default: {
    nsLookupWithCustomDns: jest.fn(),
    getDnsServers: jest.fn(),
    compareDnsServers: jest.fn(),
  },
}));

const native = ExpoNslookupModule as jest.Mocked<typeof ExpoNslookupModule>;

const resolved = {
  isPrivate: true,
  reason: "resolved" as const,
  domain: "intranet.example",
  ip: ["10.0.0.5"],
  server: "10.0.0.1",
  elapsedMs: 12,
};

beforeEach(() => jest.clearAllMocks());

describe("nsLookupWithCustomDns", () => {
  it("uses a 5000 ms timeout by default", async () => {
    native.nsLookupWithCustomDns.mockResolvedValue(resolved);

    await Nslookup.nsLookupWithCustomDns("intranet.example", ["10.0.0.1"]);

    expect(native.nsLookupWithCustomDns).toHaveBeenCalledWith(
      "intranet.example",
      ["10.0.0.1"],
      Nslookup.DEFAULT_TIMEOUT_MS,
    );
    expect(Nslookup.DEFAULT_TIMEOUT_MS).toBe(5000);
  });

  it("passes timeoutMs through unchanged", async () => {
    native.nsLookupWithCustomDns.mockResolvedValue(resolved);

    await Nslookup.nsLookupWithCustomDns("intranet.example", ["10.0.0.1"], {
      timeoutMs: 1500,
    });

    expect(native.nsLookupWithCustomDns).toHaveBeenCalledWith(
      "intranet.example",
      ["10.0.0.1"],
      1500,
    );
  });

  it("returns server: null when the native result omits it", async () => {
    const { server: _omitted, ...withoutServer } = resolved;
    native.nsLookupWithCustomDns.mockResolvedValue({
      ...withoutServer,
      isPrivate: false,
      reason: "timeout",
      ip: [],
    });

    const result = await Nslookup.nsLookupWithCustomDns("intranet.example", [
      "10.0.0.1",
    ]);

    expect(result.server).toBeNull();
    expect(result.reason).toBe("timeout");
  });

  it("returns the native result otherwise unchanged", async () => {
    native.nsLookupWithCustomDns.mockResolvedValue(resolved);

    await expect(
      Nslookup.nsLookupWithCustomDns("intranet.example", ["10.0.0.1"]),
    ).resolves.toEqual(resolved);
  });
});

describe("module surface", () => {
  it("has no default export", () => {
    expect((Nslookup as Record<string, unknown>).default).toBeUndefined();
  });

  it("exports the error codes", () => {
    expect(Nslookup.NslookupErrorCode).toEqual({
      InvalidDomain: "ERR_INVALID_DOMAIN",
      InvalidDnsServer: "ERR_INVALID_DNS_SERVER",
      InvalidTimeout: "ERR_INVALID_TIMEOUT",
      DnsConfigUnavailable: "ERR_DNS_CONFIG_UNAVAILABLE",
    });
  });

  it("forwards getDnsServers and compareDnsServers", async () => {
    native.getDnsServers.mockResolvedValue(["192.168.1.1"]);
    native.compareDnsServers.mockResolvedValue({
      deviceServers: ["192.168.1.1"],
      expectedServers: ["192.168.1.1"],
      matchedServers: ["192.168.1.1"],
      isMatch: true,
    });

    await expect(Nslookup.getDnsServers()).resolves.toEqual(["192.168.1.1"]);
    await expect(
      Nslookup.compareDnsServers(["192.168.1.1"]),
    ).resolves.toMatchObject({ isMatch: true });
    expect(native.compareDnsServers).toHaveBeenCalledWith(["192.168.1.1"]);
  });
});
