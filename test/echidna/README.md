# Echidna Framework

## Setup

Echidna is a program designed for fuzzing/property-based testing of Ethereum smart contracts. Please refer to the doc for [installation](https://github.com/crytic/echidna#installation).

Run with:

```sh
echidna test/echidna/HexOneProperties.sol  --contract HexOneProperties --config test/echidna/config1_fast.yaml
```

You can fine in `/echidna` 3 config files to run the fuzzer:

- 1< min | `config1_fast.yaml`
- 5< min | `config2_slow.yaml`
- 50 min | `config3_inDepth.yaml`

## How to work

You can find a fully functionnal example [here](https://github.com/beirao/Reliquary/tree/echidna/echidna)

### Simulate users

Admin is defined as the `address(this)` (`HexOneProperties.sol`). This should be setup in the constructor.
To do an admin external call you simply need to call the function.

```js
ERC20(token).approve(spender, value);
```

---

Users are defined with a smart contract proxy:

```js
contract User {
    function proxy(address target, bytes memory data) public returns (bool success, bytes memory err) {
        return target.call(data);
    }

    function approveERC20(ERC20 target, address spender) public {
        target.approve(spender, type(uint256).max);
    }
}
```

To make an external user call, you must do it through the proxy:

```js
(bool success, bytes memory data) = user.proxy(
    address(token),
    abi.encodeWithSelector(
        reliquary.approve.selector,
        sender,
        value
    )
);
requier(success);
```

The number of users is defined in the constructor and does not change during fuzzing.

## How is this organized

There are 3 sections:

- State updates (Here we will be defining all state update functions)
- Invariants (Here we will be defining all our invariants)
- Helpers (Free area to define helper functions)

### State updates

Basically, in this section we will create all the entry points to help the fuzzer interact with all the contracts.

So we need to create a function for each of these entry points:

_**HexOneVault**_

- `deposit(uint256 _amount, uint16 _duration)`
- `claim(uint256 _stakeId)`
- `borrow(uint256 _amount, uint256 _stakeId)`
- `liquidate(address _depositor, uint256 _stakeId)`

_**HexOneStaking**_

- `stake(address _stakeToken, uint256 _amount)`
- `unstake(address _stakeToken, uint256 _amount)`
- `claim(address _stakeToken)`

_**HexOneBootstrap**_

- `sacrifice(address _token, uint256 _amountIn, uint256 _amountOutMin)`
- `claimSacrifice()`
- `claimAirdrop()`

---

At a later stage, we can also create a function for each admin calls. (But in the first place we may just want to fix these values in the constructor)

_**HexOneVault**_

- `setBaseData(address _hexOnePriceFeed, address _hexOneStaking, address _hexOneBootstrap)`

_**HexOneStaking**_

- `setBaseData(address _hexOneVault, address _hexOneBootstrap)`
- `setStakeTokens(address[] calldata _tokens, uint16[] calldata _weights)`

_**HexOneBootstrap**_

- `setBaseData(address _hexOnePriceFeed, address _hexOneStaking, address _hexOneVault)`
- `setSacrificeTokens(address[] calldata _tokens, uint16[] calldata _multipliers)`
- `setSacrificeStart(uint256 _sacrificeStart)`
- `processSacrifice(uint256 _amountOutMinDai)`
- `startAirdrop()`

### Invariants

In this section we will define a `view` function that will _panic_ if the invariant is broken.
We must first write all invariants in English and then implement them.
