;; P2P Invoice Factoring Smart Contract
;; This contract enables peer-to-peer invoice factoring where businesses can sell their invoices
;; to investors at a discount for immediate cash flow, while investors earn returns when invoices are paid

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-INVOICE-NOT-FOUND (err u404))
(define-constant ERR-INVOICE-ALREADY-EXISTS (err u409))
(define-constant ERR-INVALID-AMOUNT (err u400))
(define-constant ERR-INVALID-DISCOUNT (err u402))
(define-constant ERR-INVOICE-ALREADY-FUNDED (err u410))
(define-constant ERR-INVOICE-NOT-FUNDED (err u411))
(define-constant ERR-INVOICE-EXPIRED (err u412))
(define-constant ERR-INSUFFICIENT-FUNDS (err u413))
(define-constant ERR-PAYMENT-ALREADY-MADE (err u414))
(define-constant ERR-INVALID-STATUS (err u415))
(define-constant ERR-UNAUTHORIZED-ACCESS (err u403))
(define-constant ERR-INVALID-DUE-DATE (err u416))
(define-constant ERR-SELF-FUNDING-NOT-ALLOWED (err u417))
(define-constant ERR-INVALID-PRINCIPAL (err u418))
(define-constant ERR-INVALID-METADATA (err u419))

;; Contract Owner
(define-constant CONTRACT-OWNER tx-sender)

;; Platform fee (in basis points, e.g., 250 = 2.5%)
(define-constant PLATFORM-FEE u250)

;; Maximum discount rate (in basis points, e.g., 2000 = 20%)
(define-constant MAX-DISCOUNT-RATE u2000)

;; Invoice Status Constants
(define-constant STATUS-PENDING u0)
(define-constant STATUS-FUNDED u1)
(define-constant STATUS-PAID u2)
(define-constant STATUS-DEFAULTED u3)
(define-constant STATUS-CANCELLED u4)

;; Data Structures
(define-map invoices
  { invoice-id: uint }
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
)

(define-map user-profiles
  { user: principal }
  {
    total-issued: uint,
    total-funded: uint,
    successful-payments: uint,
    defaulted-invoices: uint,
    reputation-score: uint,
    is-verified: bool
  }
)

(define-map invoice-bids
  { invoice-id: uint, bidder: principal }
  {
    discount-rate: uint,
    amount: uint,
    expires-at: uint,
    is-active: bool
  }
)

;; Authorized verifiers map (only these principals can verify users)
(define-map authorized-verifiers
  { verifier: principal }
  { is-authorized: bool }
)

;; Data Variables
(define-data-var next-invoice-id uint u1)
(define-data-var platform-treasury uint u0)
(define-data-var total-volume uint u0)
(define-data-var paused bool false)

;; Read-only Functions
(define-read-only (get-invoice (invoice-id uint))
  (map-get? invoices { invoice-id: invoice-id })
)

(define-read-only (get-user-profile (user principal))
  (default-to
    { total-issued: u0, total-funded: u0, successful-payments: u0, 
      defaulted-invoices: u0, reputation-score: u50, is-verified: false }
    (map-get? user-profiles { user: user })
  )
)

(define-read-only (get-invoice-bid (invoice-id uint) (bidder principal))
  (map-get? invoice-bids { invoice-id: invoice-id, bidder: bidder })
)

(define-read-only (calculate-discounted-amount (amount uint) (discount-rate uint))
  (let ((discount (/ (* amount discount-rate) u10000)))
    (- amount discount)
  )
)

(define-read-only (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM-FEE) u10000)
)

(define-read-only (get-contract-stats)
  {
    total-invoices: (- (var-get next-invoice-id) u1),
    platform-treasury: (var-get platform-treasury),
    total-volume: (var-get total-volume),
    is-paused: (var-get paused)
  }
)

(define-read-only (is-invoice-expired (invoice-id uint))
  (match (get-invoice invoice-id)
    invoice (> block-height (get due-date invoice))
    true
  )
)

(define-read-only (is-authorized-verifier (verifier principal))
  (default-to false (get is-authorized (map-get? authorized-verifiers { verifier: verifier })))
)

;; Private Functions
(define-private (update-user-reputation (user principal) (successful bool))
  (let ((profile (get-user-profile user)))
    (map-set user-profiles
      { user: user }
      (merge profile
        (if successful
          (let ((new-score (+ (get reputation-score profile) u5)))
            { 
              successful-payments: (+ (get successful-payments profile) u1),
              defaulted-invoices: (get defaulted-invoices profile),
              reputation-score: (if (> new-score u100) u100 new-score)
            }
          )
          (let ((current-score (get reputation-score profile)))
            { 
              successful-payments: (get successful-payments profile),
              defaulted-invoices: (+ (get defaulted-invoices profile) u1),
              reputation-score: (if (< current-score u10) u0 (- current-score u10))
            }
          )
        )
      )
    )
  )
)

(define-private (validate-discount-rate (discount-rate uint))
  (and (> discount-rate u0) (<= discount-rate MAX-DISCOUNT-RATE))
)

(define-private (validate-amount (amount uint))
  (> amount u0)
)

(define-private (validate-due-date (due-date uint))
  (> due-date block-height)
)

(define-private (validate-principal (address principal))
  (and 
    (is-standard address)
    (not (is-eq address 'SP000000000000000000002Q6VF78))  ;; Not burn address
    (not (is-eq address CONTRACT-OWNER))  ;; Not contract owner for debtor validation
  )
)

(define-private (validate-metadata-uri (metadata-uri (string-utf8 256)))
  (and 
    (> (len metadata-uri) u0)
    (<= (len metadata-uri) u256)
    ;; Basic validation - must start with https:// or ipfs://
    (or 
      (is-eq (unwrap-panic (slice? metadata-uri u0 u8)) u"https://")
      (is-eq (unwrap-panic (slice? metadata-uri u0 u7)) u"ipfs://")
    )
  )
)

(define-private (sanitize-user-input (user principal))
  (if (validate-principal user) user CONTRACT-OWNER)
)

;; Public Functions - Invoice Management
(define-public (create-invoice 
  (debtor principal) 
  (amount uint) 
  (discount-rate uint) 
  (due-date uint) 
  (metadata-uri (string-utf8 256))
)
  (let (
    (invoice-id (var-get next-invoice-id))
    (discounted-amount (calculate-discounted-amount amount discount-rate))
    (issuer tx-sender)
  )
    ;; Validation checks
    (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
    (asserts! (validate-amount amount) ERR-INVALID-AMOUNT)
    (asserts! (validate-discount-rate discount-rate) ERR-INVALID-DISCOUNT)
    (asserts! (validate-due-date due-date) ERR-INVALID-DUE-DATE)
    (asserts! (validate-principal debtor) ERR-INVALID-PRINCIPAL)
    (asserts! (validate-metadata-uri metadata-uri) ERR-INVALID-METADATA)
    (asserts! (not (is-eq debtor issuer)) ERR-SELF-FUNDING-NOT-ALLOWED)
    (asserts! (is-none (get-invoice invoice-id)) ERR-INVOICE-ALREADY-EXISTS)
    
    ;; Create invoice with validated inputs
    (map-set invoices
      { invoice-id: invoice-id }
      {
        issuer: issuer,
        debtor: debtor,
        amount: amount,
        discount-rate: discount-rate,
        discounted-amount: discounted-amount,
        due-date: due-date,
        created-at: block-height,
        status: STATUS-PENDING,
        funder: none,
        funded-at: none,
        paid-at: none,
        metadata-uri: metadata-uri
      }
    )
    
    ;; Update user profile
    (let ((profile (get-user-profile issuer)))
      (map-set user-profiles
        { user: issuer }
        (merge profile { total-issued: (+ (get total-issued profile) u1) })
      )
    )
    
    ;; Increment invoice ID counter
    (var-set next-invoice-id (+ invoice-id u1))
    
    (ok invoice-id)
  )
)

(define-public (fund-invoice (invoice-id uint))
  (let (
    (invoice (unwrap! (get-invoice invoice-id) ERR-INVOICE-NOT-FOUND))
    (funder tx-sender)
    (discounted-amount (get discounted-amount invoice))
    (platform-fee (calculate-platform-fee discounted-amount))
    (issuer-amount (- discounted-amount platform-fee))
  )
    ;; Validation checks
    (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status invoice) STATUS-PENDING) ERR-INVOICE-ALREADY-FUNDED)
    (asserts! (not (is-invoice-expired invoice-id)) ERR-INVOICE-EXPIRED)
    (asserts! (not (is-eq funder (get issuer invoice))) ERR-SELF-FUNDING-NOT-ALLOWED)
    
    ;; Transfer funds from funder to issuer
    (try! (stx-transfer? issuer-amount funder (get issuer invoice)))
    
    ;; Transfer platform fee
    (try! (stx-transfer? platform-fee funder CONTRACT-OWNER))
    
    ;; Update invoice status
    (map-set invoices
      { invoice-id: invoice-id }
      (merge invoice {
        status: STATUS-FUNDED,
        funder: (some funder),
        funded-at: (some block-height)
      })
    )
    
    ;; Update user profiles
    (let ((funder-profile (get-user-profile funder)))
      (map-set user-profiles
        { user: funder }
        (merge funder-profile { total-funded: (+ (get total-funded funder-profile) u1) })
      )
    )
    
    ;; Update contract stats
    (var-set platform-treasury (+ (var-get platform-treasury) platform-fee))
    (var-set total-volume (+ (var-get total-volume) discounted-amount))
    
    (ok true)
  )
)

(define-public (pay-invoice (invoice-id uint))
  (let (
    (invoice (unwrap! (get-invoice invoice-id) ERR-INVOICE-NOT-FOUND))
    (payer tx-sender)
    (amount (get amount invoice))
    (funder (unwrap! (get funder invoice) ERR-INVOICE-NOT-FUNDED))
  )
    ;; Validation checks
    (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status invoice) STATUS-FUNDED) ERR-INVALID-STATUS)
    (asserts! (or (is-eq payer (get debtor invoice)) (is-eq payer (get issuer invoice))) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Transfer payment to funder
    (try! (stx-transfer? amount payer funder))
    
    ;; Update invoice status
    (map-set invoices
      { invoice-id: invoice-id }
      (merge invoice {
        status: STATUS-PAID,
        paid-at: (some block-height)
      })
    )
    
    ;; Update reputations
    (update-user-reputation (get issuer invoice) true)
    (update-user-reputation funder true)
    
    (ok true)
  )
)

(define-public (mark-default (invoice-id uint))
  (let (
    (invoice (unwrap! (get-invoice invoice-id) ERR-INVOICE-NOT-FOUND))
    (caller tx-sender)
    (funder (unwrap! (get funder invoice) ERR-INVOICE-NOT-FUNDED))
  )
    ;; Only funder or contract owner can mark as default
    (asserts! (or (is-eq caller funder) (is-eq caller CONTRACT-OWNER)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get status invoice) STATUS-FUNDED) ERR-INVALID-STATUS)
    (asserts! (is-invoice-expired invoice-id) ERR-INVOICE-EXPIRED)
    
    ;; Update invoice status
    (map-set invoices
      { invoice-id: invoice-id }
      (merge invoice { status: STATUS-DEFAULTED })
    )
    
    ;; Update reputation negatively for issuer
    (update-user-reputation (get issuer invoice) false)
    
    (ok true)
  )
)

(define-public (cancel-invoice (invoice-id uint))
  (let (
    (invoice (unwrap! (get-invoice invoice-id) ERR-INVOICE-NOT-FOUND))
    (caller tx-sender)
  )
    ;; Only issuer can cancel unfunded invoice
    (asserts! (is-eq caller (get issuer invoice)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get status invoice) STATUS-PENDING) ERR-INVALID-STATUS)
    
    ;; Update invoice status
    (map-set invoices
      { invoice-id: invoice-id }
      (merge invoice { status: STATUS-CANCELLED })
    )
    
    (ok true)
  )
)

;; Public Functions - Bidding System
(define-public (place-bid (invoice-id uint) (discount-rate uint) (expires-at uint))
  (let (
    (invoice (unwrap! (get-invoice invoice-id) ERR-INVOICE-NOT-FOUND))
    (bidder tx-sender)
    (discounted-amount (calculate-discounted-amount (get amount invoice) discount-rate))
  )
    ;; Validation checks
    (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status invoice) STATUS-PENDING) ERR-INVALID-STATUS)
    (asserts! (validate-discount-rate discount-rate) ERR-INVALID-DISCOUNT)
    (asserts! (> expires-at block-height) ERR-INVALID-DUE-DATE)
    (asserts! (not (is-eq bidder (get issuer invoice))) ERR-SELF-FUNDING-NOT-ALLOWED)
    
    ;; Place bid
    (map-set invoice-bids
      { invoice-id: invoice-id, bidder: bidder }
      {
        discount-rate: discount-rate,
        amount: discounted-amount,
        expires-at: expires-at,
        is-active: true
      }
    )
    
    (ok true)
  )
)

(define-public (accept-bid (invoice-id uint) (bidder principal))
  (let (
    (invoice (unwrap! (get-invoice invoice-id) ERR-INVOICE-NOT-FOUND))
    (bid (unwrap! (get-invoice-bid invoice-id bidder) ERR-INVOICE-NOT-FOUND))
    (caller tx-sender)
    (bid-amount (get amount bid))
    (platform-fee (calculate-platform-fee bid-amount))
    (issuer-amount (- bid-amount platform-fee))
  )
    ;; Validation checks
    (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq caller (get issuer invoice)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get status invoice) STATUS-PENDING) ERR-INVALID-STATUS)
    (asserts! (get is-active bid) ERR-INVALID-STATUS)
    (asserts! (> (get expires-at bid) block-height) ERR-INVOICE-EXPIRED)
    (asserts! (validate-principal bidder) ERR-INVALID-PRINCIPAL)
    
    ;; Transfer funds
    (try! (stx-transfer? issuer-amount bidder caller))
    (try! (stx-transfer? platform-fee bidder CONTRACT-OWNER))
    
    ;; Update invoice
    (map-set invoices
      { invoice-id: invoice-id }
      (merge invoice {
        status: STATUS-FUNDED,
        funder: (some bidder),
        funded-at: (some block-height),
        discount-rate: (get discount-rate bid),
        discounted-amount: bid-amount
      })
    )
    
    ;; Deactivate bid
    (map-set invoice-bids
      { invoice-id: invoice-id, bidder: bidder }
      (merge bid { is-active: false })
    )
    
    ;; Update stats
    (var-set platform-treasury (+ (var-get platform-treasury) platform-fee))
    (var-set total-volume (+ (var-get total-volume) bid-amount))
    
    (ok true)
  )
)

;; Public Functions - User Profile Management
(define-public (verify-user (user principal))
  (let ((validated-user (sanitize-user-input user)))
    ;; Only contract owner or authorized verifiers can verify users
    (asserts! (or 
      (is-eq tx-sender CONTRACT-OWNER) 
      (is-authorized-verifier tx-sender)
    ) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (validate-principal validated-user) ERR-INVALID-PRINCIPAL)
    
    (let ((profile (get-user-profile validated-user)))
      (map-set user-profiles
        { user: validated-user }
        (merge profile { is-verified: true })
      )
    )
    
    (ok true)
  )
)

;; Admin Functions
(define-public (add-authorized-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (validate-principal verifier) ERR-INVALID-PRINCIPAL)
    
    (map-set authorized-verifiers
      { verifier: verifier }
      { is-authorized: true }
    )
    
    (ok true)
  )
)

(define-public (remove-authorized-verifier (verifier principal))
  (let ((validated-verifier (sanitize-user-input verifier)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (validate-principal validated-verifier) ERR-INVALID-PRINCIPAL)
    
    (map-set authorized-verifiers
      { verifier: validated-verifier }
      { is-authorized: false }
    )
    
    (ok true)
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    (var-set paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    (var-set paused false)
    (ok true)
  )
)

(define-public (withdraw-treasury (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (<= amount (var-get platform-treasury)) ERR-INSUFFICIENT-FUNDS)
    
    (try! (stx-transfer? amount (as-contract tx-sender) CONTRACT-OWNER))
    (var-set platform-treasury (- (var-get platform-treasury) amount))
    
    (ok true)
  )
)