# lottery
A lottery implemented in a solidity smart contract.<br/><br/>
This contract is not currently deployed or operational, and is merely used as an educational tool to demonstrate certain smart contract functionality.

## Summary
This smart contract lottery demonstrates how a game of random chance can be run in a way that is both centralized (i.e. the smart contract has an owner/operator) and fair (i.e. players cannot be cheated out of their money).

## Features
### Randomness
Each time a drawing is done with two or more players, the contract spends Chainlink tokens to pay for a randomly generated number. See the Chainlink website for more information:<br/>
https://chain.link/

### Segregation of Funds
The contract separates any native coins into 5 categories:
- Bonus Prize Pool - The funds that have optionally been added to "sweeten the pot" and provide a bigger prize.
- Claimable Balance Pool - The funds that have not yet been claimed.
- Contract Funds - The general funds owned by the contract.
- Player Prize Pool - The funds players have paid to purchase tickets.
- Refund Pool - The funds that were in the Player Prize Pool for a drawing that was canceled.

Anything else not accounted for is considered to be extra funds. The operator can only withdraw from the contract funds and the extra funds.<br/><br/>
(Extra funds are certain coins that may be added to the contract outside of normal lottery activities, such as through a coinbase transaction. Also, tokens are not included in this accounting and can be freely withdrawn by the contract operator, with the exception of Chainlink which has a minimum balance requirement.)

## Lottery
### Rules
Each drawing will take place according to the following process:
1. Once a drawing is active, players can purchase whole number quantities of tickets.
2. After enough time has passed, a winning ticket can be drawn. If there are two or more players, Chainlink is used to fairly determine the winner.
3. The current drawing is concluded, prizes are rewarded, and the next drawing automatically begins.

Note that although the operator is expected to carry out these steps, the contract is designed so that anyone is allowed to do them. For example, if a player feels that a drawing has gone on for too long, they may draw the winning ticket and end the current drawing themselves. This prevents a negligent operator from causing player's funds to be trapped.

### Prize
For a given drawing, let **P** be the Player Prize Pool (the total amount of ticket sales from all players), and let **B** be the Bonus Prize Pool.
The owner and operator each get a small cut of **P**, and then the rest of **P** and all of **B** goes to the winner.

### Cancellation
The operator may choose to pay a penalty fee and cancel the current drawing. In the event of a cancellation, players who have purchased tickets may request a refund manually. The penalty payment will be added to the bonus prize pool.

### Self-Destruct
The owner may call self-destruct on the contract, however two conditions must first be met:
- The contract must be marked as corrupt (described below).
- After that, a grace period must pass to allow players to withdraw any funds from the contract.

The owner may call a "validate" function that performs certain checks:
- Check for a hard fork.
- Check to see if the block time has drifted too high.
- Check for a locked contract.
- Check for the incorrect accounting of the contract balance.
- Check for a player prize pool that doesn't match the money used to purchase tickets.
- Check for an incorrect counting of tickets.
- Check to see if a drawing has not ended in a long time.

If any of these has occurred, the contract is marked as corrupt.

## Contract
The lottery contract is not currently deployed.<br/><br/>
Some properties of the contract:
- The contract has both an owner and an operator address, allowing for a separation of responsibilities.
- The contract has certain fail-safes built into it:
  - ERC20 tokens, as well as native coins, can be withdrawn from the contract by the owner.
  - The owner can disable the reentrancy lock if the contract is in an unanticipated state.
  - A new owner/operator must claim the position before the transfer is complete (i.e. you cannot accidentally give a position to an invalid address).
