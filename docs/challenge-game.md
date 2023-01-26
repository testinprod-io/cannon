# Challenge Game

*In some documents in Cannon wiki, the term `Challenge Game` means only the bisection part. But in this document, we call the whole process of EVM fault-proof a Challenge Game.*

Cannon is an interactive fault-proof system for an EVM block transition. As you can find from this definition, there are interactive actions between participants to prove whether the proposed block transition is correct/incorrect. We call this process a Challenge Game.

## Goal
The goal of this game is to prove the correctness of the EVM block transition result on the L1 (Ethereum).

## Block transition program
As mentioned above, what we want to prove is the `Block transition`. It means getting the state of the n+1th block after executing transactions starting from the nth block state. And the `state` is the EVM state, including the entire data stored in the blockchain, which could be represented as a state root hash of its Merkle trie.

Because we should emulate the block transition on the L1 chain(EVM) to prove the correctness, We implemented a simple block transition program called minigeth and compiled it to MIPS bytecode.

During the challenge game, we have to deal with the `MIPS state`, which includes the memory and registers of the MIPS virtual machine.

## Role
In this game, there are two roles: Challenger and Defender.

- **Challenger** claims the proposed EVM state is invalid.
- **Defender** insists the proposed EVM state is correct, usually the proposer itself(in the Optimism bedrock, sequencer)

## Challenge initiation
Challenger can start the challenge game by sending an initiation transaction to the challenge contract on the L1 chain. The initiation transaction should contain the following information about the claim.
- **Block number**: Number of the block before the block transition
- **Block header**: Block header after block transition, including transaction list to execute.
- **EVM state root**: The EVM state root after the block transition that the challenger claims
- **MIPS state root**: The root hash of the block transition program's final MIPS state.

## Interactive Binary Search
After the challenge initiation, the challenger and the defender find a single MIPS instruction that they do not agree with each other through an interactive binary search.

The goal of each binary search step is to compare the MIPS machine state after the instruction in the middle of the instruction window, which is a sequence of MIPS instructions. The challenger and defender agreed on the state before the window but disagreed on the state after the window. After comparison, the next step is repeated in the bisected window until only one instruction is left.

The comparison in each step consists of two actions: propose and respond.
- **Propose**: The challenger bisects the window, picks an instruction in the middle, and runs the MIPS machine on off-chain until the selected instruction. Then submits the machine state to the challenge contract.
- **Respond**: The defender runs the own MIPS machine until the corresponding instruction, then submits the machine state.

If the two submitted hashes are identical, it means they agreed on the intermediate machine state. So the first instruction of the next window should be the selected instruction.

If two hashes are different, it means they disagreed on the intermediate machine state. Then the last instruction of the next window should be the selected instruction.

Although this process looks like a simple binary search, it's one of the most important designs in the Cannon system because we can reduce the amount of computation that should be run on the L1 chain. So we can prove any rollup that uses anything for an execution engine, regardless of the amount of computation.


## On-chain Single instruction Emulation
Through the interactive binary search, we found a single MIPS instruction to verify. Challenger and defender agreed on the MIPS machine state before the instruction but disagreed on the state after the instruction. We have to run the single instruction on the L1 chain to determine the valid result. Execution of MIPS instructions is relatively easy due to the simple design of MIPS architecture, but we also need memory, register, and EVM storage for emulation. There are some special tricks to implement these things on the L1 chain.
- **Preimage Oracle**: To emulate EVM transactions, we need access to EVM storage. e.g., account balance and contract variables. But we cannot use the original EVM storage because accessing past data on EVM is impossible. Of course, we can't provide whole data through transactions because it's too huge. Instead, we implement Preimage Oracle to give only a small piece of data we need to access. `[TODO: link to preimage oracle docs]`
- **Merkle-Patricia Trie Memory**: Implementing MIPS memory and registers looks quite simple, with just simple mapping in Solidity. But remember that we should compare the MIPS states of challenger and defender in the interactive binary search. It should be tough to compare all values in the mapping. So Cannon stores these values in a Merkle-Patricia Trie, the same as Ethereum uses, so we can compare the snapshots of the MIPS virtual machine with only state root hash.

Thanks to these magics, we can run the MIPS instruction for the EVM emulation on the L1 chain with few transactions. After that, our Ethereum will judge the winner of the challenge game.
