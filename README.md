# FHEVM Skill for AI Coding Agents

> A production-ready SKILL.md (and supporting files) that enables AI coding agents — Claude Code, Cursor, Windsurf — to accurately build, test, and deploy confidential smart contracts on the Zama Protocol.

---

## The problem

AI coding agents have no built-in knowledge of FHE or FHEVM. Ask Claude Code or Cursor to "write a confidential voting contract" without any context and you'll get incorrect patterns, missing ACL calls, wrong import paths, and broken logic.

The most common mistakes:
- Using the old `TFHE` import instead of `FHE`
- Forgetting `FHE.allowThis()` after every arithmetic operation
- Trying to branch on `ebool` with `if/else`
- Using encrypted divisors with `FHE.div`
- Missing `inputProof` in function signatures

## The solution

Drop `SKILL.md` into your AI coding environment. The agent now has accurate, up-to-date knowledge of the entire FHEVM development workflow — contracts, testing, deployment, and frontend.

## What's included

```
SKILL.md                        ← the main skill file (drop into Claude Code / Cursor)
examples/
  ConfidentialCounter.sol       ← hello-world: encrypted counter
  ConfidentialVoting.sol        ← encrypted voting with public reveal
  ERC7984MintableToken.sol      ← confidential ERC-7984 token
  ConfidentialVoting.test.ts    ← Hardhat tests with mock FHE
  fhevm-frontend.ts             ← fhevmjs integration patterns
templates/
  ConfidentialBase.sol          ← minimal FHEVM contract template
CLAUDE.md                       ← session context for Claude Code
```

## Topics covered in SKILL.md

1. FHEVM architecture — how FHE works on-chain, the co-processor stack
2. Development environment — Hardhat template setup, .env config
3. Encrypted types — euint8–256, ebool, eaddress, externalEuintXX
4. FHE operations — arithmetic, bitwise, comparison, FHE.select, randomness
5. Access control — FHE.allowThis, FHE.allow, FHE.allowTransient, FHE.makePubliclyDecryptable
6. Input proofs — externalEuintXX + inputProof pattern, FHE.fromExternal
7. User decryption — EIP-712 signing flow, fhevmjs reencrypt
8. Public decryption — oracle callback pattern, FHE.makePubliclyDecryptable
9. Frontend integration — fhevmjs initialization, createEncryptedInput, all input types
10. Testing — mock FHE mode, hardhat-fhevm plugin, testnet validation
11. Anti-patterns — 7 documented common mistakes with correct fixes
12. ERC-7984 + OpenZeppelin Confidential Contracts — full token workflow

## How to use with Claude Code

```bash
# In your project root:
cp /path/to/SKILL.md ./SKILL.md

# Start Claude Code and paste this prompt:
```

```
Read SKILL.md. I want to build a confidential sealed-bid auction using FHEVM.
Bids should be encrypted, the highest bid wins, and losing bids are never revealed.
Use the current FHE API with externalEuint64 + inputProof pattern.
Include: correct imports, ZamaEthereumConfig, ACL setup, FHE.select for comparison.
```

## How to use with Cursor / Windsurf

Add `SKILL.md` to your project root. These agents automatically pick up `.md` files as context. Alternatively, add it to your `.cursorrules` or reference it directly in your prompt.

## Validation

The skill was tested against these prompts in Claude Code:

| Prompt | Result |
|---|---|
| "Write a confidential voting contract" | Compiles, correct ACL, FHE.select used |
| "How do I build a confidential ERC-7984 token?" | Correct OZ imports, mint/burn pattern |
| "What's wrong with my contract?" + missing allowThis | Skill catches it |
| "Encrypt a value in the frontend and send to contract" | Correct fhevmjs pattern |

## Running the examples

```bash
# Clone this repo
git clone https://github.com/yourusername/zama-fhevm-skill
cd zama-fhevm-skill

# Fork the FHEVM template first
git clone https://github.com/zama-ai/fhevm-react-template my-project
cd my-project && npm install

# Copy examples into the template's contracts/ and test/ directories
cp ../examples/ConfidentialVoting.sol contracts/
cp ../examples/ConfidentialVoting.test.ts test/

# Run tests in mock FHE mode (no testnet needed)
npx hardhat test

# Deploy to Sepolia
npx hardhat run scripts/deploy.ts --network sepolia
```

## Tech stack

| Tool | Version |
|---|---|
| Solidity | ^0.8.27 |
| @fhevm/solidity | latest |
| @openzeppelin/confidential-contracts | latest |
| Hardhat | ^2.22 |
| fhevmjs | latest |
| ethers | ^6 |

## License

MIT
