# CLAUDE.md — Zama FHEVM Skill Hackathon

## what we're building
A production-ready SKILL.md (and supporting files) that enables AI coding agents — Claude Code, Cursor, Windsurf — to accurately build, test, and deploy confidential smart contracts using the Zama Protocol / FHEVM.

This is NOT a dApp. The deliverable IS the skill file itself.

## hackathon
- Program: Zama Developer Program Mainnet Season 2 - Bounty Track
- Deadline: May 10, 2026 (23:59 AOE)
- Prize: 3,000 cUSDT (1st: 1,500 / 2nd: 1,000 / 3rd: 500)
- Submission: skill files + 3-min demo video (real person, no AI voice)

## deliverables
1. SKILL.md — comprehensive FHEVM AI agent skill file
2. examples/ — working Solidity + TypeScript code examples
3. templates/ — ready-to-use contract templates
4. README.md — submission README
5. VIDEO_SCRIPT.md — demo video script

## judging criteria (in order of weight)
1. Accuracy — correct, working FHEVM code; up-to-date API refs
2. Completeness — full workflow: contracts, testing, deployment, frontend
3. Agent effectiveness — can a dev go from prompt to working dApp?
4. Code quality — clean, well-documented, best practices
5. Structure — clear separation of reference, examples, templates
6. Error prevention — prevents common FHEVM pitfalls

## phase status
- [x] PHASE 0: Research + setup
- [ ] PHASE 1: Write SKILL.md core content
- [ ] PHASE 2: Write supporting examples
- [ ] PHASE 3: Test with Claude Code (validate skill works)
- [ ] PHASE 4: Record video, submit

## key technical facts (DO NOT get these wrong)
- Import path: `@fhevm/solidity/lib/FHE.sol`
- Config: inherit `ZamaEthereumConfig` from `@fhevm/solidity/config/ZamaConfig.sol`
- External inputs use `externalEuintXX` type + `bytes inputProof` pair
- Convert inputs: `FHE.fromExternal(encryptedValue, inputProof)`
- Access control: ALWAYS call `FHE.allowThis()` after storing encrypted values
- Branching: use `FHE.select(condition, a, b)` — never `if` on ebool
- div/rem only works with PLAINTEXT divisors
- View functions CANNOT return encrypted values to unallowed callers
- No encryption in constructors (use `FHE.asEuintX(plaintext)` for init)
- ERC-7984 package: `@openzeppelin/confidential-contracts`
