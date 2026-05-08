# FHEVM Skill — AI Agent Guide for Confidential Smart Contracts

> Drop this file into Claude Code, Cursor, Windsurf, or any AI coding agent.
> When a developer asks "build me a confidential voting contract" — this is what makes the agent produce correct, working FHEVM code.

---

## 1. What Is FHEVM and How It Works

FHEVM is Zama's framework for confidential smart contracts on EVM-compatible chains. It uses **Fully Homomorphic Encryption (FHE)** — meaning the EVM can compute on encrypted data without ever decrypting it.

**The key difference from standard Solidity:**
- Sensitive values are stored as **ciphertext handles** (encrypted integers on a co-processor)
- Computation happens on the co-processor, not in the EVM directly
- The EVM stores handles (pointers), not plaintext values
- Decryption requires explicit authorization + off-chain key management

**The stack:**
```
User's browser (fhevmjs)
    → encrypts input locally
    → generates inputProof
    → sends encrypted tx to EVM

EVM (your Solidity contract)
    → receives externalEuintXX + inputProof
    → calls FHE.fromExternal() to validate + store
    → performs FHE ops (add, compare, select…)
    → enforces ACL with FHE.allowThis / FHE.allow

FHEVM Co-processor + KMS
    → executes actual FHE computation
    → handles threshold decryption via MPC
    → returns results to Gateway

Gateway (for decryption requests)
    → re-encrypts for specific user (userDecrypt)
    → or returns plaintext (publicDecrypt)
```

**Network:** Zama Protocol runs on Ethereum Sepolia testnet and Ethereum Mainnet.

---

## 2. Development Environment Setup

### Fork the official template first
```bash
# This is the fastest setup — fork this repo
# https://github.com/zama-ai/fhevm-react-template

git clone https://github.com/zama-ai/fhevm-react-template
cd fhevm-react-template
npm install
```

### Environment variables (.env)
```bash
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
PRIVATE_KEY=0x...
```

### Key packages
```bash
npm install @fhevm/solidity
npm install @openzeppelin/confidential-contracts  # for ERC-7984
```

### hardhat.config.ts — required structure
```typescript
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111,
    },
  },
};

export default config;
```

---

## 3. Encrypted Types

### Type reference
| Solidity Type | Size | Description |
|---|---|---|
| `euint8` | 8-bit | Encrypted unsigned integer |
| `euint16` | 16-bit | Encrypted unsigned integer |
| `euint32` | 32-bit | Encrypted unsigned integer |
| `euint64` | 64-bit | Most common — used for balances, amounts |
| `euint128` | 128-bit | Large integers |
| `euint256` | 256-bit | Max precision |
| `ebool` | 1-bit | Encrypted boolean |
| `eaddress` | 160-bit | Encrypted Ethereum address |
| `externalEuint8` … `externalEuint256` | — | Input type for user-provided encrypted values |
| `externalEbool` | — | Input type for user-provided encrypted booleans |
| `externalEaddress` | — | Input type for user-provided encrypted addresses |

### Required imports
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint64, euint32, euint8, ebool, eaddress,
         externalEuint64, externalEuint8, externalEbool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
```

### Casting between types
```solidity
// Plaintext to encrypted
euint64 val = FHE.asEuint64(0);         // from literal
euint64 val = FHE.asEuint64(someUint64); // from plaintext variable
ebool   flag = FHE.asEbool(true);
eaddress addr = FHE.asEaddress(msg.sender);

// Encrypted to encrypted (cross-type cast)
euint64 big   = FHE.asEuint64(small32);  // euint32 → euint64
euint32 small = FHE.asEuint32(big64);    // euint64 → euint32 (truncates)
ebool   flag  = FHE.asEbool(uint8Val);   // euint8 → ebool
```

### Converting user inputs
```solidity
// User provides externalEuintXX + bytes inputProof
// ALWAYS validate with FHE.fromExternal before using
function deposit(externalEuint64 encryptedAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
    // amount is now a validated, usable handle
}
```

---

## 4. FHE Operations

All operations are on **encrypted values**. Results are encrypted handles.

### Arithmetic
```solidity
euint64 sum  = FHE.add(a, b);    // a + b (both encrypted)
euint64 diff = FHE.sub(a, b);    // a - b
euint64 prod = FHE.mul(a, b);    // a * b (expensive — use carefully)
euint64 div  = FHE.div(a, 3);    // a / 3 — ONLY plaintext divisor
euint64 rem  = FHE.rem(a, 4);    // a % 4 — ONLY plaintext divisor
euint64 mn   = FHE.min(a, b);    // min(a, b)
euint64 mx   = FHE.max(a, b);    // max(a, b)
euint64 neg  = FHE.neg(a);       // -a
```

### Bitwise
```solidity
euint64 and  = FHE.and(a, b);
euint64 or   = FHE.or(a, b);
euint64 xor  = FHE.xor(a, b);
euint64 not  = FHE.not(a);       // bitwise NOT
euint64 shl  = FHE.shl(a, 3);   // left shift by plaintext
euint64 shr  = FHE.shr(a, 2);   // right shift by plaintext
```

### Comparison (return ebool)
```solidity
ebool eq = FHE.eq(a, b);   // a == b
ebool ne = FHE.ne(a, b);   // a != b
ebool lt = FHE.lt(a, b);   // a < b
ebool le = FHE.le(a, b);   // a <= b
ebool gt = FHE.gt(a, b);   // a > b
ebool ge = FHE.ge(a, b);   // a >= b
```

### Conditional / Branching — CRITICAL
```solidity
// CORRECT — encrypted ternary, never if/else on ebool
euint64 result = FHE.select(condition, valueIfTrue, valueIfFalse);

// WRONG — you cannot branch on encrypted bool this way
// if (condition) { ... }  ← this will not compile or will leak
```

### Randomness
```solidity
euint8  r8  = FHE.randEuint8();
euint32 r32 = FHE.randEuint32();
euint64 r64 = FHE.randEuint64();
// Note: randomness is deterministic within a block — do not rely on it for security-critical sampling
```

---

## 5. Access Control (ACL)

The ACL (Access Control List) controls who can interact with encrypted handles. **Missing ACL calls are the #1 bug in FHEVM contracts.**

### Core functions

```solidity
// Allow THIS contract to keep using the handle (persistent)
// Call this every time you store or update an encrypted value
FHE.allowThis(encryptedValue);

// Allow a specific address to use the handle (persistent)
// Call this to grant a user or another contract access
FHE.allow(encryptedValue, targetAddress);

// Allow a specific address for this transaction only (transient)
// Use for inter-contract calls in the same tx
FHE.allowTransient(encryptedValue, targetAddress);

// Make a ciphertext publicly decryptable forever (no auth needed)
FHE.makePubliclyDecryptable(encryptedValue);

// Check: does msg.sender currently have access?
FHE.isSenderAllowed(encryptedValue);  // reverts if not

// Check: is a ciphertext publicly decryptable?
bool isPublic = FHE.isPubliclyDecryptable(encryptedValue);
```

### When to call what

```solidity
// Pattern: store encrypted value → immediately allow the contract
function setValue(externalEuint64 enc, bytes calldata proof) external {
    storedValue = FHE.fromExternal(enc, proof);
    FHE.allowThis(storedValue);          // ← REQUIRED: let contract use it next time
    FHE.allow(storedValue, msg.sender);  // ← let user read their own value
}

// Pattern: update encrypted value
function addToValue(externalEuint64 enc, bytes calldata proof) external {
    euint64 input = FHE.fromExternal(enc, proof);
    FHE.allowThis(input);  // not strictly needed here but safe practice

    storedValue = FHE.add(storedValue, input);
    FHE.allowThis(storedValue);  // ← REQUIRED on every re-assignment
}

// Pattern: pass encrypted value to another contract
function forwardToVault(euint64 amount) internal {
    FHE.allowTransient(amount, address(vault));
    vault.deposit(amount);
}
```

### Constructor pattern (initialization)
```solidity
constructor() {
    // Use FHE.asEuintX for plaintext initialization
    totalVotes = FHE.asEuint64(0);
    FHE.allowThis(totalVotes);  // ← required even in constructor
}
```

---

## 6. Input Proofs

**Why they exist:** When a user encrypts data off-chain (in their browser via fhevmjs), the network needs proof that the ciphertext is well-formed and belongs to this specific contract/user. The `inputProof` is that proof.

### Solidity pattern

```solidity
// In function signature:
// - externalEuintXX is the encrypted value (NOT euintXX)
// - bytes calldata inputProof is ALWAYS paired with it

function submitBid(
    externalEuint64 encryptedBid,
    bytes calldata inputProof
) external {
    // FHE.fromExternal validates the proof and returns a usable handle
    euint64 bid = FHE.fromExternal(encryptedBid, inputProof);
    FHE.allowThis(bid);
    bids[msg.sender] = bid;
    FHE.allow(bids[msg.sender], msg.sender);
}
```

### Multiple encrypted inputs — one proof handles all
```solidity
function submitOrder(
    externalEuint64 encryptedAmount,
    externalEuint64 encryptedPrice,
    bytes calldata inputProof  // ← single proof covers both inputs
) external {
    euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
    euint64 price  = FHE.fromExternal(encryptedPrice, inputProof);
    // ...
}
```

### TypeScript — creating encrypted inputs (fhevmjs)
```typescript
import { createInstance } from "fhevmjs";

const instance = await createInstance({
  chainId: 11155111,  // Sepolia
  networkUrl: process.env.SEPOLIA_RPC_URL,
  gatewayUrl: "https://gateway.sepolia.zama.ai",
  aclAddress: "YOUR_ACL_ADDRESS",  // see: https://docs.zama.org/protocol/protocol-apps/addresses/testnet/sepolia
});

// Encrypt input for a specific contract
const encrypted = await instance.createEncryptedInput(
  contractAddress,
  userAddress
);
encrypted.add64(BigInt(1000));  // add a euint64 value
const { handles, inputProof } = encrypted.encrypt();

// handles[0] is the externalEuint64 to pass to the contract
// inputProof is the bytes to pass as inputProof
```

---

## 7. User Decryption (Re-encryption)

Users can decrypt values they have ACL access to. This happens **client-side** — the user's browser gets a re-encrypted version only they can decrypt.

### The flow
1. User generates an ephemeral keypair in their browser
2. User signs the public key using EIP-712 (proves ownership)
3. Client calls contract's view function to get the ciphertext handle
4. Client sends handle + signature to the Gateway
5. Gateway re-encrypts under user's public key
6. Client decrypts locally with private key

### Solidity — expose the handle
```solidity
// Return the encrypted handle — callers must have ACL access
function getMyBid() external view returns (euint64) {
    require(FHE.isSenderAllowed(bids[msg.sender]), "Not allowed");
    return bids[msg.sender];
}
```

### TypeScript — full user decryption flow
```typescript
import { createInstance } from "fhevmjs";
import { BrowserProvider } from "ethers";

const provider = new BrowserProvider(window.ethereum);
const signer = await provider.getSigner();
const userAddress = await signer.getAddress();

const instance = await createInstance({
  chainId: 11155111,
  networkUrl: process.env.SEPOLIA_RPC_URL,
  gatewayUrl: "https://gateway.sepolia.zama.ai",
  aclAddress: "YOUR_ACL_ADDRESS",
});

// Step 1: generate keypair
const { publicKey, privateKey } = instance.generateKeypair();

// Step 2: create EIP-712 object and sign
const eip712 = instance.createEIP712(publicKey, contractAddress);
const signature = await signer.signTypedData(
  eip712.domain,
  { Reencrypt: eip712.types.Reencrypt },
  eip712.message
);

// Step 3: call contract to get the handle
const encryptedHandle = await contract.getMyBid();

// Step 4: re-encrypt via Gateway (happens inside reencrypt)
const decryptedValue = await instance.reencrypt(
  encryptedHandle,
  privateKey,
  publicKey,
  signature,
  contractAddress,
  userAddress
);

console.log("Your bid:", decryptedValue);
```

---

## 8. Public Decryption

For values that should become public (e.g., vote results after an election ends), use public decryption. This is on-chain and triggers a callback.

### Pattern: request public decrypt + callback

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { IDecryptionOracle } from "@fhevm/solidity/oracle/IDecryptionOracle.sol";

contract ConfidentialVoting is ZamaEthereumConfig {
    euint64 private encryptedYesVotes;
    euint64 private encryptedNoVotes;
    uint64 public yesVotes;
    uint64 public noVotes;
    bool public resultsRevealed;

    address public decryptionOracle;

    event ResultsRequested(uint256 requestId);
    event ResultsRevealed(uint64 yes, uint64 no);

    // Request decryption — results arrive asynchronously via callback
    function revealResults() external {
        // Mark ciphertexts as publicly decryptable
        FHE.makePubliclyDecryptable(encryptedYesVotes);
        FHE.makePubliclyDecryptable(encryptedNoVotes);

        // Request decryption from the oracle
        uint256[] memory handles = new uint256[](2);
        handles[0] = euint64.unwrap(encryptedYesVotes);
        handles[1] = euint64.unwrap(encryptedNoVotes);

        uint256 requestId = IDecryptionOracle(decryptionOracle)
            .requestDecryption(handles, this.decryptionCallback.selector, 0);

        emit ResultsRequested(requestId);
    }

    // Callback called by the decryption oracle with plaintext results
    function decryptionCallback(
        uint256, /* requestId */
        bytes[] memory decryptedValues
    ) external {
        require(msg.sender == decryptionOracle, "Only oracle");
        yesVotes = abi.decode(decryptedValues[0], (uint64));
        noVotes  = abi.decode(decryptedValues[1], (uint64));
        resultsRevealed = true;
        emit ResultsRevealed(yesVotes, noVotes);
    }
}
```

---

## 9. Frontend Integration (fhevmjs)

### Installation
```bash
npm install fhevmjs
# For React (Vite recommended — CRA has WASM issues)
npm create vite@latest my-app -- --template react-ts
cd my-app && npm install fhevmjs ethers
```

### Initialization
```typescript
import { initFhevm, createInstance } from "fhevmjs";

// Call once at app startup
await initFhevm();  // loads WASM — required before createInstance

const instance = await createInstance({
  chainId: 11155111,   // Sepolia testnet
  networkUrl: "https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY",
  gatewayUrl: "https://gateway.sepolia.zama.ai",
  aclAddress: "0x...",   // see Sepolia registry in Zama docs
});
```

### Encrypting input and calling a contract
```typescript
import { ethers } from "ethers";
import { createInstance } from "fhevmjs";

async function encryptAndVote(voteYes: boolean) {
  const provider = new ethers.BrowserProvider(window.ethereum);
  const signer = await provider.getSigner();
  const user = await signer.getAddress();

  const encInput = await instance.createEncryptedInput(
    CONTRACT_ADDRESS,
    user
  );
  encInput.addBool(voteYes);  // adds an ebool
  const { handles, inputProof } = encInput.encrypt();

  // handles[0] = externalEbool value
  // inputProof  = bytes proof

  const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, signer);
  const tx = await contract.vote(handles[0], inputProof);
  await tx.wait();
}
```

### Common fhevmjs input methods
```typescript
const encInput = await instance.createEncryptedInput(contractAddr, userAddr);

encInput.addBool(true);            // → externalEbool
encInput.add8(42);                 // → externalEuint8
encInput.add16(1000);              // → externalEuint16
encInput.add32(99999);             // → externalEuint32
encInput.add64(BigInt("100000")); // → externalEuint64
encInput.addAddress("0x...");      // → externalEaddress

const { handles, inputProof } = encInput.encrypt();
// handles[0], handles[1], ... match the order of add* calls
// inputProof covers all of them
```

---

## 10. Testing FHEVM Contracts

### Mock mode (local dev — no testnet needed)
```typescript
import { ethers, fhevm } from "hardhat";
// The fhevm hardhat plugin provides mock FHE in local tests
// No actual encryption — great for fast iteration

describe("ConfidentialVoting", function () {
  let voting: any;
  let owner: any, voter1: any, voter2: any;

  beforeEach(async function () {
    [owner, voter1, voter2] = await ethers.getSigners();
    const Voting = await ethers.getContractFactory("ConfidentialVoting");
    voting = await Voting.deploy();
  });

  it("should cast an encrypted vote", async function () {
    // Create encrypted input for voter1
    const instance = await fhevm.createFhevmInstance();
    const encInput = await instance.createEncryptedInput(
      voting.target,
      voter1.address
    );
    encInput.addBool(true);  // voting yes
    const { handles, inputProof } = encInput.encrypt();

    const tx = await voting.connect(voter1).vote(handles[0], inputProof);
    await tx.wait();

    // Verify voted status
    expect(await voting.hasVoted(voter1.address)).to.equal(true);
  });

  it("should decrypt yes vote count after reveal", async function () {
    // ... cast votes ...

    // Trigger public decryption (mock mode resolves synchronously)
    await voting.connect(owner).revealResults();
    await fhevm.awaitAllDecryptionResults();

    expect(await voting.yesVotes()).to.equal(1n);
    expect(await voting.noVotes()).to.equal(0n);
  });
});
```

### Testnet testing
For real Sepolia tests, set `PRIVATE_KEY` and `SEPOLIA_RPC_URL` and run:
```bash
npx hardhat test --network sepolia
```
Note: testnet FHE operations are slower (~5–30s per operation). Use mock for development, testnet for final validation.

---

## 11. Common Anti-Patterns and Mistakes

### ❌ Missing FHE.allowThis() after storing
```solidity
// WRONG — contract can't read its own value next call
function store(externalEuint64 enc, bytes calldata proof) external {
    storedValue = FHE.fromExternal(enc, proof);
    // forgot: FHE.allowThis(storedValue);
}

// CORRECT
function store(externalEuint64 enc, bytes calldata proof) external {
    storedValue = FHE.fromExternal(enc, proof);
    FHE.allowThis(storedValue);   // ← always
    FHE.allow(storedValue, msg.sender);
}
```

### ❌ Branching on encrypted boolean
```solidity
// WRONG — ebool cannot be used in if/require
function maybeAdd(ebool condition, euint64 a, euint64 b) internal {
    if (condition) { result = FHE.add(result, a); }  // compile error / logic leak
}

// CORRECT — use FHE.select
function maybeAdd(ebool condition, euint64 a, euint64 b) internal {
    result = FHE.select(condition, FHE.add(result, a), result);
}
```

### ❌ Encrypting in constructor using user input
```solidity
// WRONG — constructor runs on deployment, not per-user
constructor(externalEuint64 enc, bytes calldata proof) {
    secret = FHE.fromExternal(enc, proof);  // inputProof doesn't work in constructor
}

// CORRECT — use plaintext initializer or separate init function
constructor() {
    secret = FHE.asEuint64(0);
    FHE.allowThis(secret);
}
```

### ❌ Returning encrypted value from view function without ACL
```solidity
// WRONG — anyone calling this gets a handle they can't use (misleading)
function getBalance(address user) external view returns (euint64) {
    return balances[user];  // missing ACL check
}

// CORRECT
function getBalance(address user) external view returns (euint64) {
    require(
        msg.sender == user || FHE.isSenderAllowed(balances[user]),
        "Not authorized"
    );
    return balances[user];
}
```

### ❌ Using div/rem with encrypted divisors
```solidity
// WRONG — encrypted divisors not supported
euint64 result = FHE.div(a, b);  // b is euint64 — fails

// CORRECT — divisor must be plaintext
euint64 result = FHE.div(a, 4);  // 4 is plaintext uint
```

### ❌ Forgetting FHE.allowThis() after arithmetic operations
```solidity
// WRONG — result of add() is a new handle — old ACL doesn't carry
function increment() external {
    totalVotes = FHE.add(totalVotes, FHE.asEuint64(1));
    // forgot: FHE.allowThis(totalVotes);
}

// CORRECT
function increment() external {
    totalVotes = FHE.add(totalVotes, FHE.asEuint64(1));
    FHE.allowThis(totalVotes);  // ← new handle after every operation
}
```

### ❌ Using wrong import path (old TFHE vs new FHE)
```solidity
// WRONG — old API, don't use
import { TFHE } from "@fhevm/solidity/lib/TFHE.sol";

// CORRECT — current API
import { FHE } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
```

### ❌ Expecting encrypted operations to revert on failure
```solidity
// NOTE: FHE operations often don't revert on logical errors
// e.g. subtraction underflow returns 0, not a revert
// Use FHE.select patterns to handle these cases safely

// Pattern for safe subtraction:
function safeSubtract(euint64 a, euint64 b) internal returns (euint64) {
    ebool canSubtract = FHE.ge(a, b);              // a >= b?
    euint64 safeResult = FHE.sub(a, b);            // would underflow if a < b
    return FHE.select(canSubtract, safeResult, a); // return a unchanged if can't subtract
}
```

---

## 12. OpenZeppelin Confidential Contracts + ERC-7984

ERC-7984 is the confidential token standard — "encrypted ERC-20". Balances and transfer amounts are stored as `euint64` handles.

### Installation
```bash
npm install @openzeppelin/confidential-contracts
```

### Minimal ERC-7984 token
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { FHE, externalEuint64, euint64 } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { ERC7984 } from "@openzeppelin/confidential-contracts/token/ERC7984/ERC7984.sol";

contract MyConfidentialToken is ZamaEthereumConfig, ERC7984, Ownable2Step {
    constructor(
        address owner,
        string memory name_,
        string memory symbol_,
        string memory contractURI_
    ) ERC7984(name_, symbol_, contractURI_) Ownable(owner) {}

    // Mint with encrypted amount (only owner)
    function mint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external onlyOwner {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        _mint(to, amount);
    }

    // Burn with encrypted amount
    function burn(
        address from,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external onlyOwner {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        _burn(from, amount);
    }
}
```

### Key ERC-7984 interface
```solidity
// Transfer functions (8 variants — combinations of with/without proof, transferFrom/transfer)
confidentialTransfer(address to, externalEuint64 amount, bytes inputProof) → euint64
confidentialTransfer(address to, euint64 amount) → euint64           // no proof — caller already allowed
confidentialTransferFrom(address from, address to, externalEuint64 amount, bytes proof) → euint64
confidentialTransferFrom(address from, address to, euint64 amount) → euint64

// Read (encrypted — user must be allowed)
confidentialBalanceOf(address account) → euint64
confidentialTotalSupply() → euint64
```

### Wrapping ERC-20 → ERC-7984
```solidity
import { ERC7984ERC20Wrapper } from "@openzeppelin/confidential-contracts/token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";

// Inherit from wrapper — users call wrap(amount) to convert ERC-20 → ERC-7984
// and unwrap to go back
contract WrappedToken is ZamaEthereumConfig, ERC7984ERC20Wrapper {
    constructor(IERC20 underlying_)
        ERC7984ERC20Wrapper(underlying_)
        ERC7984("Wrapped MyToken", "wMYT", "https://example.com")
    {}
}
```

### Available OZ Confidential Contract extensions
| Extension | Purpose |
|---|---|
| `ERC7984ERC20Wrapper` | Wrap ERC-20 into confidential ERC-7984 |
| `ERC7984Freezable` | Freeze accounts (role-based) |
| `ERC7984Restricted` | Blocklist / allowlist accounts |
| `ERC7984ObserverAccess` | Grant read access to a third party |
| `ERC7984Omnibus` | Encrypted sub-account transfers (exchange use) |
| `ERC7984Rwa` | RWA compliance: compliance checks + forced transfers |
| `ERC7984Votes` | Governance voting on confidential token balances |

---

## Quick Reference: Full Contract Example

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * ConfidentialVoting — encrypted votes, public result reveal
 * 
 * Demonstrates: input proofs, ACL, FHE.select, FHE.add, public decryption
 */

import { FHE, euint64, ebool, externalEbool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract ConfidentialVoting is ZamaEthereumConfig {
    euint64 private encryptedYesVotes;
    euint64 private encryptedNoVotes;

    mapping(address => bool) public hasVoted;
    bool public votingOpen;
    address public owner;

    uint64 public yesVotes;
    uint64 public noVotes;
    bool public resultsRevealed;

    event Voted(address indexed voter);
    event VotingClosed();

    constructor() {
        owner = msg.sender;
        votingOpen = true;

        // Initialize encrypted counters
        encryptedYesVotes = FHE.asEuint64(0);
        encryptedNoVotes  = FHE.asEuint64(0);
        FHE.allowThis(encryptedYesVotes);
        FHE.allowThis(encryptedNoVotes);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function vote(externalEbool support, bytes calldata inputProof) external {
        require(votingOpen, "Voting closed");
        require(!hasVoted[msg.sender], "Already voted");

        hasVoted[msg.sender] = true;

        // Validate + convert input
        ebool isYes = FHE.fromExternal(support, inputProof);
        FHE.allowThis(isYes);

        // FHE.select — never use if/else on encrypted bool
        euint64 one  = FHE.asEuint64(1);
        euint64 zero = FHE.asEuint64(0);

        encryptedYesVotes = FHE.add(encryptedYesVotes, FHE.select(isYes, one, zero));
        encryptedNoVotes  = FHE.add(encryptedNoVotes,  FHE.select(isYes, zero, one));

        // Re-allow after every arithmetic operation
        FHE.allowThis(encryptedYesVotes);
        FHE.allowThis(encryptedNoVotes);

        emit Voted(msg.sender);
    }

    function closeVoting() external onlyOwner {
        votingOpen = false;
        // Make results publicly decryptable
        FHE.makePubliclyDecryptable(encryptedYesVotes);
        FHE.makePubliclyDecryptable(encryptedNoVotes);
        emit VotingClosed();
    }
}
```

---

## Resources

| Resource | URL |
|---|---|
| Zama Protocol Docs | https://docs.zama.org/protocol/ |
| FHEVM React Template | https://github.com/zama-ai/fhevm-react-template |
| FHEVM Solidity Library | https://github.com/zama-ai/fhevm-solidity |
| OZ Confidential Contracts | https://github.com/OpenZeppelin/openzeppelin-confidential-contracts |
| OZ Confidential Docs | https://docs.openzeppelin.com/confidential-contracts/ |
| ERC-7984 Docs | https://docs.openzeppelin.com/confidential-contracts/token |
| FHEVM Examples | https://docs.zama.org/protocol/examples/ |
| Sepolia Token Registry | https://docs.zama.org/protocol/protocol-apps/addresses/testnet/sepolia |
| FHEVM Bootcamp | https://www.mintlify.com/Himess/fhevm-bootcamp/introduction |
