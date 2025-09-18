# P2P Invoice Factoring Smart Contract

A peer-to-peer invoice factoring platform built on the Stacks blockchain that enables businesses to sell their invoices to investors at a discount for immediate cash flow, while investors earn returns when invoices are paid.

## Overview

This smart contract facilitates a decentralized marketplace where:
- **Businesses (Issuers)** can create invoices and sell them at a discount for immediate liquidity
- **Investors (Funders)** can purchase invoices and earn returns when debtors pay
- **Debtors** pay invoices directly to funders
- The platform collects fees and maintains user reputation scores

## Features

### Core Functionality
- **Invoice Creation**: Businesses can create invoices with customizable discount rates
- **Direct Funding**: Investors can fund invoices immediately at listed rates
- **Bidding System**: Investors can place competitive bids on invoices
- **Payment Processing**: Secure payment handling with automatic status updates
- **Reputation System**: User scoring based on payment history and defaults
- **User Verification**: KYC/verification system for enhanced trust

### Security Features
- **Input Validation**: Comprehensive validation of all user inputs
- **Access Controls**: Role-based permissions for different operations
- **Emergency Controls**: Contract pause/unpause functionality
- **Anti-Self-Dealing**: Prevention of self-funding scenarios
- **Expiration Handling**: Automatic handling of expired invoices

## Contract Constants

### Fee Structure
- **Platform Fee**: 2.5% (250 basis points) on all funded invoices
- **Maximum Discount Rate**: 20% (2000 basis points)

### Invoice Status Types
- `STATUS-PENDING` (0): Invoice created, awaiting funding
- `STATUS-FUNDED` (1): Invoice funded by an investor
- `STATUS-PAID` (2): Invoice paid by debtor
- `STATUS-DEFAULTED` (3): Invoice marked as defaulted
- `STATUS-CANCELLED` (4): Invoice cancelled by issuer

## Data Structures

### Invoice Structure
```clarity
{
  issuer: principal,
  debtor: principal,
  amount: uint,
  discount-rate: uint,
  discounted-amount: uint,
  due-date: uint,
  created-at: uint,
  status: uint,
  funder: (optional principal),
  funded-at: (optional uint),
  paid-at: (optional uint),
  metadata-uri: (string-utf8 256)
}
```

### User Profile Structure
```clarity
{
  total-issued: uint,
  total-funded: uint,
  successful-payments: uint,
  defaulted-invoices: uint,
  reputation-score: uint,
  is-verified: bool
}
```

### Bid Structure
```clarity
{
  discount-rate: uint,
  amount: uint,
  expires-at: uint,
  is-active: bool
}
```

## Public Functions

### Invoice Management

#### `create-invoice`
Creates a new invoice for factoring.
```clarity
(create-invoice debtor amount discount-rate due-date metadata-uri)
```
**Parameters:**
- `debtor`: Principal who owes the invoice amount
- `amount`: Full invoice amount in microSTX
- `discount-rate`: Discount rate in basis points (e.g., 500 = 5%)
- `due-date`: Block height when invoice is due
- `metadata-uri`: URI pointing to invoice metadata (HTTPS or IPFS)

**Returns:** Invoice ID on success

#### `fund-invoice`
Funds an existing invoice at the listed discount rate.
```clarity
(fund-invoice invoice-id)
```

#### `pay-invoice`
Pays a funded invoice (callable by debtor or issuer).
```clarity
(pay-invoice invoice-id)
```

#### `cancel-invoice`
Cancels an unfunded invoice (issuer only).
```clarity
(cancel-invoice invoice-id)
```

#### `mark-default`
Marks an expired, funded invoice as defaulted.
```clarity
(mark-default invoice-id)
```

### Bidding System

#### `place-bid`
Places a competitive bid on a pending invoice.
```clarity
(place-bid invoice-id discount-rate expires-at)
```

#### `accept-bid`
Accepts a bid on an invoice (issuer only).
```clarity
(accept-bid invoice-id bidder)
```

### User Management

#### `verify-user`
Verifies a user (admin or authorized verifier only).
```clarity
(verify-user user)
```

## Read-Only Functions

### Data Retrieval
- `get-invoice`: Retrieve invoice details by ID
- `get-user-profile`: Get user profile and reputation data
- `get-invoice-bid`: Get bid details for specific invoice/bidder
- `get-contract-stats`: Get platform statistics

### Calculations
- `calculate-discounted-amount`: Calculate discounted amount for given rate
- `calculate-platform-fee`: Calculate platform fee for given amount
- `is-invoice-expired`: Check if invoice has expired
- `is-authorized-verifier`: Check if principal is authorized verifier

## Admin Functions

### Access Control
- `add-authorized-verifier`: Add new authorized verifier
- `remove-authorized-verifier`: Remove authorized verifier

### Emergency Controls
- `pause-contract`: Pause all contract operations
- `unpause-contract`: Resume contract operations
- `withdraw-treasury`: Withdraw accumulated platform fees

## Usage Examples

### Creating an Invoice
```clarity
;; Create a $1000 invoice with 5% discount, due in 1000 blocks
(contract-call? .invoice-factoring create-invoice
  'SP1234...DEBTOR     ;; debtor address
  u1000000000          ;; $1000 in microSTX
  u500                 ;; 5% discount rate
  (+ block-height u1000) ;; due date
  u"https://example.com/invoice-metadata.json"
)
```

### Funding an Invoice
```clarity
;; Fund invoice #1
(contract-call? .invoice-factoring fund-invoice u1)
```

### Placing a Bid
```clarity
;; Place bid with 3% discount rate, expires in 100 blocks
(contract-call? .invoice-factoring place-bid
  u1                    ;; invoice ID
  u300                  ;; 3% discount rate
  (+ block-height u100) ;; bid expiration
)
```

## Security Considerations

### Input Validation
- All amounts must be greater than 0
- Discount rates must be between 0.01% and 20%
- Due dates must be in the future
- Principal addresses are validated against standard format
- Metadata URIs must use HTTPS or IPFS protocols

### Access Controls
- Only invoice issuers can cancel their unfunded invoices
- Only debtors or issuers can pay invoices
- Only funders or contract owner can mark defaults
- Only contract owner can manage verifiers and emergency controls

### Economic Safeguards
- Platform fee automatically deducted on funding
- Self-funding prevention (issuers cannot fund their own invoices)
- Maximum discount rate caps to prevent exploitation
- Reputation system incentivizes good behavior

## Error Handling

The contract includes comprehensive error handling with descriptive error codes:
- `ERR-NOT-AUTHORIZED` (401): Unauthorized operation
- `ERR-INVOICE-NOT-FOUND` (404): Invoice does not exist
- `ERR-INVALID-AMOUNT` (400): Invalid amount specified
- `ERR-INVOICE-EXPIRED` (412): Invoice past due date
- And many more detailed error conditions

## Deployment

### Prerequisites
- Stacks blockchain testnet/mainnet access
- Clarity CLI or compatible deployment tool
- STX tokens for deployment transaction fees

### Deployment Steps
1. Compile the contract using Clarity CLI
2. Deploy to testnet for testing
3. Verify contract functionality
4. Deploy to mainnet for production use

## Testing

### Recommended Test Cases
- Invoice creation with various parameters
- Funding scenarios (direct funding vs bidding)
- Payment processing and status updates
- Default handling for expired invoices
- Reputation system updates
- Access control enforcement
- Emergency pause/unpause functionality

## Integration

### Frontend Integration
The contract exposes read-only functions for building user interfaces:
- Display available invoices for funding
- Show user profiles and reputation scores
- Track invoice status and payment history
- Calculate returns and fees

### API Endpoints
Build APIs around the read-only functions:
- `/invoices` - List available invoices
- `/users/{address}` - Get user profile
- `/invoices/{id}` - Get invoice details
- `/stats` - Platform statistics