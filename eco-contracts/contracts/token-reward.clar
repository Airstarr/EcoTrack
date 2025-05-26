
;; title: token-reward
;; version:
;; summary:
;; description: Handles token creation, distribution and balance management

;; traits
;;

;; token definitions
;;


;; Define the token
(define-fungible-token eco-token)

;; constants
;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-POINTS (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))

;; data vars
;; Data variables for token metadata
(define-data-var token-name (string-ascii 32) "ECO-TOKEN")
(define-data-var token-symbol (string-ascii 10) "ECO")
(define-data-var token-decimals uint u6)
(define-data-var token-supply uint u0)

;; Initialize contract owner
(define-data-var contract-owner principal tx-sender)

;; data maps
;;
;; Maps for managing balances and allowances
(define-map user-balances principal uint)
(define-map token-allowances 
    { owner: principal, spender: principal } 
    uint
)
;; public functions
;;
;; Mint new tokens
;; @param recipient: Address to receive tokens
;; @param amount: Amount of tokens to mint
(define-public (mint-tokens (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> amount u0) ERR-INVALID-POINTS)
        (try! (ft-mint? eco-token amount recipient))
        (var-set token-supply (+ (var-get token-supply) amount))
        (ok true))
)

;; Transfer tokens between accounts
;; @param sender: Address sending tokens
;; @param recipient: Address receiving tokens
;; @param amount: Amount to transfer
(define-public (transfer (sender principal) (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
        (asserts! (>= (ft-get-balance eco-token sender) amount) ERR-INSUFFICIENT-BALANCE)
        (try! (ft-transfer? eco-token amount sender recipient))
        (ok true))
)

;; Approve spender to transfer tokens
;; @param spender: Address being authorized to spend
;; @param amount: Amount authorized to spend
(define-public (approve (spender principal) (amount uint))
    (begin
        (map-set token-allowances 
            { owner: tx-sender, spender: spender } 
            amount)
        (ok true))
)

;; Transfer contract ownership
;; @param new-owner: New contract owner address
(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)))

;; read only functions
;;
;; Get token balance
;; @param owner: Address to check balance for
(define-read-only (get-balance (owner principal))
    (ok (ft-get-balance eco-token owner)))

;; Get allowance
;; @param owner: Token owner
;; @param spender: Authorized spender
(define-read-only (get-allowance (owner principal) (spender principal))
    (ok (default-to u0 
        (map-get? token-allowances { owner: owner, spender: spender }))))

;; Get total supply
(define-read-only (get-total-supply)
    (ok (var-get token-supply)))

;; Get token info
(define-read-only (get-token-info)
    (ok {
        name: (var-get token-name),
        symbol: (var-get token-symbol),
        decimals: (var-get token-decimals),
        supply: (var-get token-supply)
    }))