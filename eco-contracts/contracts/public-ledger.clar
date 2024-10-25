;; title: public-ledger.clar
;; 
;; Manages the logging and verification of eco-friendly actions

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-ACTION (err u101))
(define-constant ERR-ALREADY-LOGGED (err u102))
(define-constant ERR-INVALID-POINTS (err u103))

;; Action types and their point values
(define-constant ACTION-RECYCLE u10)
(define-constant ACTION-PLANT-TREE u50)
(define-constant ACTION-USE-PUBLIC-TRANSPORT u15)
(define-constant ACTION-SOLAR-PANEL u100)

;; Point constraints
(define-constant MIN-POINTS u1)
(define-constant MAX-POINTS u1000)

;; Data maps for storing actions
(define-map actions 
    { user: principal, action-id: uint } 
    { 
        action-type: uint,
        timestamp: uint,
        points: uint,
        verified: bool,
        verifier: (optional principal)
    })

;; Track number of actions per user
(define-map user-action-count principal uint)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Global action counter
(define-data-var action-counter uint u0)

;; Log a new eco-friendly action
;; @param action-type: Type of action performed
;; @param points: Points to award for the action
(define-public (log-action (action-type uint) (points uint))
    (let ((action-id (+ (var-get action-counter) u1)))
        (asserts! (and (>= points MIN-POINTS) (<= points MAX-POINTS)) ERR-INVALID-POINTS)
        (asserts! (is-valid-action-type action-type) ERR-INVALID-ACTION)
        
        ;; Record the action
        (map-set actions 
            { user: tx-sender, action-id: action-id }
            { 
                action-type: action-type,
                timestamp: block-height,
                points: points,
                verified: false,
                verifier: none
            })
        
        ;; Update counters
        (var-set action-counter action-id)
        (map-set user-action-count 
            tx-sender 
            (+ (default-to u0 (map-get? user-action-count tx-sender)) u1))
        
        (ok action-id)))

;; Verify an action and trigger reward
;; @param user: User who performed the action
;; @param action-id: ID of the action to verify
(define-public (verify-action (user principal) (action-id uint))
    (let ((action (unwrap! (map-get? actions { user: user, action-id: action-id }) ERR-INVALID-ACTION)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get verified action)) ERR-ALREADY-LOGGED)
        
        ;; Update action verification status
        (map-set actions 
            { user: user, action-id: action-id }
            (merge action { 
                verified: true,
                verifier: (some tx-sender)
            }))
        
        ;; Trigger token reward
        (try! (contract-call? .token-reward mint-tokens user (get points action)))
        (ok true))
)

;; Check if action type is valid
(define-private (is-valid-action-type (action-type uint))
    (or 
        (is-eq action-type ACTION-RECYCLE)
        (is-eq action-type ACTION-PLANT-TREE)
        (is-eq action-type ACTION-USE-PUBLIC-TRANSPORT)
        (is-eq action-type ACTION-SOLAR-PANEL)))

;; Get user's action count
;; @param user: User to check
(define-read-only (get-user-action-count (user principal))
    (ok (default-to u0 (map-get? user-action-count user))))

;; Get action details
;; @param user: User who performed the action
;; @param action-id: ID of the action
(define-read-only (get-action-details (user principal) (action-id uint))
    (ok (map-get? actions { user: user, action-id: action-id })))

;; Get latest action ID
(define-read-only (get-latest-action-id)
    (ok (var-get action-counter)))

;; Check if user has performed specific action type
;; @param user: User to check
;; @param action-type: Type of action to check
(define-read-only (has-performed-action (user principal) (action-type uint))
    (ok (is-some (map-get? actions 
        { user: user, action-id: (var-get action-counter) }))))

;; Transfer contract ownership
;; @param new-owner: New contract owner address
(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)))
