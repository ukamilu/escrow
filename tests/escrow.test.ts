
import { beforeEach, describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const contractName = "escrow";
const ERR = {
  UNAUTHORIZED: Cl.uint(4),
  INVALID_STATE: Cl.uint(3),
};

const STATE = {
  FUNDED: Cl.uint(0),
  RELEASED: Cl.uint(1),
  DISPUTED: Cl.uint(2),
  EXPIRED: Cl.uint(3),
};

const DEFAULT_AMOUNT = 2_000_000n; // 2 STX (in micro-STX)
const DEFAULT_TIMEOUT = 200n; // >= MIN-TIMEOUT-BLOCKS (144)
const MIN_TIMEOUT = 144n;

const accounts = simnet.getAccounts();
const buyer = accounts.get("wallet_1")!;
const seller = accounts.get("wallet_2")!;
const arbitrator = accounts.get("wallet_3")!;

const createEscrow = (id: bigint, timeout: bigint = DEFAULT_TIMEOUT, amount: bigint = DEFAULT_AMOUNT) => {
  return simnet.callPublicFn(
    contractName,
    "create-escrow-with-timeout",
    [Cl.uint(id), Cl.standardPrincipal(seller), Cl.standardPrincipal(arbitrator), Cl.uint(amount), Cl.uint(timeout)],
    buyer,
  );
};

const getState = (id: bigint) =>
  simnet.callReadOnlyFn(contractName, "get-escrow-state", [Cl.uint(id)], buyer).result;

const getTimeout = (id: bigint) =>
  simnet.callReadOnlyFn(contractName, "get-escrow-timeout-blocks", [Cl.uint(id)], buyer).result;

describe("escrow core flows", () => {
  beforeEach(() => {
    // sanity check that a fresh simnet session is available
    expect(simnet.blockHeight).toBeGreaterThan(0);
  });

  it("lets the buyer create then release funds to the seller", () => {
    const id = 1n;
    const creation = createEscrow(id);
    expect(creation.result).toBeOk(Cl.bool(true));
    expect(getState(id)).toBeOk(STATE.FUNDED);

    const release = simnet.callPublicFn(contractName, "release", [Cl.uint(id)], buyer);
    expect(release.result).toBeOk(Cl.bool(true));
    expect(getState(id)).toBeOk(STATE.RELEASED);
  });

  it("allows dispute by a party and arbitrator resolves to seller", () => {
    const id = 2n;
    createEscrow(id);

    const dispute = simnet.callPublicFn(contractName, "dispute", [Cl.uint(id)], seller);
    expect(dispute.result).toBeOk(Cl.bool(true));
    expect(getState(id)).toBeOk(STATE.DISPUTED);

    const resolution = simnet.callPublicFn(
      contractName,
      "resolve-dispute",
      [Cl.uint(id), Cl.bool(true)],
      arbitrator,
    );
    expect(resolution.result).toBeOk(Cl.bool(true));
    expect(getState(id)).toBeOk(STATE.RELEASED);
  });

  it("allows arbitrator to resolve dispute in favor of buyer", () => {
    const id = 3n;
    createEscrow(id);

    const dispute = simnet.callPublicFn(contractName, "dispute", [Cl.uint(id)], buyer);
    expect(dispute.result).toBeOk(Cl.bool(true));
    expect(getState(id)).toBeOk(STATE.DISPUTED);

    const resolution = simnet.callPublicFn(
      contractName,
      "resolve-dispute",
      [Cl.uint(id), Cl.bool(false)],
      arbitrator,
    );
    expect(resolution.result).toBeOk(Cl.bool(true));
    expect(getState(id)).toBeOk(STATE.RELEASED);
  });

  it("lets buyer reclaim funds after expiry", () => {
    const id = 4n;
    createEscrow(id, MIN_TIMEOUT);

    // advance chain beyond timeout
    for (let i = 0; i <= Number(MIN_TIMEOUT); i++) {
      simnet.mineBlock([]);
    }

    const claim = simnet.callPublicFn(contractName, "claim-expired", [Cl.uint(id)], buyer);
    expect(claim.result).toBeOk(Cl.bool(true));
    expect(getState(id)).toBeOk(STATE.EXPIRED);

    const expired = simnet.callReadOnlyFn(contractName, "is-expired", [Cl.uint(id)], buyer);
    expect(expired.result).toBeOk(Cl.bool(true));
  });

  it("extends timeout only after both buyer and seller approve", () => {
    const id = 5n;
    const initialTimeout = 200n;
    const proposedTimeout = 300n;
    createEscrow(id, initialTimeout);
    expect(getTimeout(id)).toBeOk(Cl.uint(initialTimeout));

    const proposal = simnet.callPublicFn(
      contractName,
      "propose-timeout-extension",
      [Cl.uint(id), Cl.uint(proposedTimeout)],
      buyer,
    );
    expect(proposal.result).toBeOk(Cl.bool(true));

    const approval = simnet.callPublicFn(contractName, "approve-timeout-extension", [Cl.uint(id)], seller);
    expect(approval.result).toBeOk(Cl.bool(true));
    expect(getTimeout(id)).toBeOk(Cl.uint(proposedTimeout));

    // extension proposal should be cleared
    const pending = simnet.getMapEntry(contractName, "timeout-extensions", Cl.uint(id));
    expect(pending).toBeNone();
  });

  it("blocks unauthorized release attempts", () => {
    const id = 6n;
    createEscrow(id);
    const attempt = simnet.callPublicFn(contractName, "release", [Cl.uint(id)], seller);
    expect(attempt.result).toBeErr(ERR.UNAUTHORIZED);
    expect(getState(id)).toBeOk(STATE.FUNDED);
  });

  it("refuses operations in the wrong state", () => {
    const id = 7n;
    createEscrow(id);
    // Resolve without dispute
    const invalidResolve = simnet.callPublicFn(
      contractName,
      "resolve-dispute",
      [Cl.uint(id), Cl.bool(true)],
      arbitrator,
    );
    expect(invalidResolve.result).toBeErr(ERR.INVALID_STATE);
  });
});
