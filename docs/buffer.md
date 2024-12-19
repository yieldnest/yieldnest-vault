# Buffer Strategy

## Overview
This document provides an outline for a Buffer Strategy that is used to facilitate instant withdraws for the MAX Vaults. A 4626 Vault is required with a common underlying asset as the MAX Vault. The vault employs yield strategies to maximize returns. The buffer strategy must provide instantaneous withdraws to the MAX vaults.

## Buffer Strategy Vault
The Buffer Strategy Vault must be 4626 compliant and with instantaneous withdraws for use as the primary source of withdraws for the Max vaults. Assets held in the buffer are deployed to yield earning strategies to optimize capital efficiency. 

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
    participant YieldStrategy

    rect rgba(0, 255, 0, 0.1)
    User ->> Vault: deposit(assets, receiver)
    Vault ->> Vault: _mint(User, shares)
    Vault ->> BufferStrategy: deposit(assets, Vault)
    Vault ->> WETH: transferFrom(User, BufferStrategy, assets)
    BufferStrategy ->> BufferStrategy: _mint(Vault, shares)
    BufferStrategy ->> Vault: return shares
    BufferStrategy ->> YieldStrategy: deposit(assets, BufferStrategy)
    YieldStrategy ->> YieldStrategy: _mint(BufferStrategy, shares)
    YieldStrategy ->> BufferStrategy: returns shares
    Vault ->> User: return shares
    end

    rect rgba(255, 0, 0, 0.1)
    User ->> Vault: withdraw(assets, receiver, owner)
    Vault ->> BufferStrategy: withdraw(assets, receiver, owner)
    BufferStrategy ->> YieldStrategy: withdraw(assets, BufferStrategy)
    Vault ->> Vault: _burn(User, assets)

    BufferStrategy ->> BufferStrategy: _burn(Vault, assets)
    YieldStrategy ->> YieldStrategy: _burn(BufferStrategy, assets)
    WETH ->> User: transferFrom(YieldStrategy, User, assets)
    end


