# Yearn V3 Vault with WETH

## Overview
This document provides an outline for a Yearn V3 Vault that uses WETH (Wrapped Ether) as the underlying asset. The vault employs two high-yield strategies from Yearn to maximize returns. Additionally, a buffer strategy is used to hold funds for withdrawals in the max vaults.

## Table of Contents
1. Introduction
2. Vault Setup
3. Strategies
    - Strategy 1: High-Yield Strategy A
    - Strategy 2: High-Yield Strategy B
4. Buffer Strategy
5. Diagram

## Introduction
The Buffer Strategy is used as the primary source of withdraws for the Max vaults. Assets held in the buffer are deployed to a Yearn V3 valut to optimize captial accross several yield strategies. 

## Strategies
### Strategy 1: Yield Strategy A
This strategy focuses on maximizing returns by investing the base underlying asset of the MAX Vault to yield opportunities within the Yearn ecosystem.

### Strategy 2: Yield Strategy B
This strategy complements Strategy 1 by diversifying investments into another set of yield opportunities, further optimizing returns.

## Buffer Strategy
The buffer strategy is used to hold a portion of the funds in a readily accessible manner to facilitate quick withdrawals. This ensures that users can withdraw their funds from the max vaults without delay by drawing on liquid 4626 funds held in the yearn vault.


## Diagram

```mermaid
sequenceDiagram
    participant User
    participant Vault
    participant BufferStrategy
    participant WETH

    User ->> Vault: deposit(assets, receiver)
    Vault ->> Vault: _mint(User, shares)
    Vault ->> User: return shares
    Vault ->> BufferStrategy: deposit(assets, Vault)
    BufferStrategy ->> WETH: transferFrom(Vault, BufferStrategy, assets)
    BufferStrategy ->> BufferStrategy: _mint(Vault, shares)
    BufferStrategy ->> Vault: return shares

    User ->> Vault: withdraw(assets, receiver, owner)
    Vault ->> BufferStrategy: withdraw(assets, receiver, owner)
    BufferStrategy ->> WETH: transferFrom(BufferStrategy, Vault, assets)
    BufferStrategy ->> BufferStrategy: _burn(Vault, assets)
    Vault ->> Vault: _burn(User, assets)
    Vault ->> User: return assets