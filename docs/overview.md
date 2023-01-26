# Cannon Overview

The Cannon is an on-chain interactive dispute engine implementing EVM-equivalent fault proofs. What is this, and how does it work?

In the Optimism Bedrock system, an L2 validator follows the L1 chain, monitoring it for transaction batches and output commitments (which commit to the chain state after a specific block). Both of these things are submitted by the sequencer.

An L2 validator reruns the batches locally and verifies that the state they obtain matches the sequencer's output commitments. If they don't, they can challenge the results on L1. This is where Cannon enters the scene.

The goal of the whole affair is to prove, on the L1 chain, that the sequencer lied about the results of the block transition. But we can't rerun the entire block on L1 — that would be too expensive.

We should reduce the amount of computation running on the L1. Recalling a bit of computer science knowledge, all computation, including EVM block transition, consists of a sequence of instructions of the target machine. This means that if the sequencer lied about block transition, we could find the first instruction that is not computed correctly, and it's the only thing we should run on the L1 chain.

For practical reasons, we decided to use the MIPS machine to implement this methodology. It means we compile the EVM block transition code(from geth) into MIPS code and verify it on the L1 - EVM in this case.

In summary, we decompose the problem into two steps:
1. Among MIPS instructions of the block transition program, Find a single instruction such that the challenger and the defender (i.e., the sequencer) agree on the memory (RAM & registries) before that step but disagree on the memory after that step.
2. Run that single instruction on the L1 chain. MIPS instruction can be executed on the L1 by a simple on-chain MIPS interpreter (only 400 lines!).

For more information on how this is possible and how it has been implemented, please see the [challenge game docs](./challenge-game.md)

And another essential concept is the preimage oracle that makes all of this possible. Please read the following article for a detailed explanation of preimage oracle: `[TODO: link to preimage oracle docs]`

## Components
Cannon has the following components to implement an efficient and robust fault-proof system. For a detailed description of each component, see the respective documentation. 
### minigeth
An EVM block transition program which is the target of fault-proof. `[TODO: link to minigeth docs]`
### mipigo
A tool to compile minigeth to MIPS code, and modify something for on-chain execution. `[TODO: link to mipigo docs]`
### mipsevm
A tool to run the compiled MIPS binary locally to participate in the challenge game. `[TODO: link to mipsevm docs]`
### contracts
L1 contracts for the challenge game and MIPS emulation, written in Solidity. You can find docs as comments in each contract file.