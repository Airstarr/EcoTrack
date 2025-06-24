;; Eco Leaderboards & Rankings Smart Contract
;; Tracks user contributions across different eco-categories and maintains rankings

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_CATEGORY (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_USER_NOT_FOUND (err u103))
(define-constant ERR_INSUFFICIENT_BALANCE (err u104))

;; Eco Categories
(define-constant CATEGORY_TREES_PLANTED u1)
(define-constant CATEGORY_RECYCLING u2)
(define-constant CATEGORY_ENERGY_SAVED u3)
(define-constant CATEGORY_WATER_CONSERVED u4)
(define-constant CATEGORY_CARBON_REDUCED u5)

;; Reward amounts (in micro-STX)
(define-constant MONTHLY_TOP_REWARD u1000000) ;; 1 STX
(define-constant YEARLY_TOP_REWARD u5000000)  ;; 5 STX
(define-constant PARTICIPATION_REWARD u100000) ;; 0.1 STX

;; Data Variables
(define-data-var total-users uint u0)
(define-data-var current-month uint u1)
(define-data-var current-year uint u2024)

;; Data Maps

;; User profiles
(define-map users
  { user: principal }
  {
    total-score: uint,
    monthly-score: uint,
    yearly-score: uint,
    last-activity: uint,
    rewards-earned: uint
  }
)

;; Category contributions for each user
(define-map user-category-contributions
  { user: principal, category: uint }
  {
    total-amount: uint,
    monthly-amount: uint,
    yearly-amount: uint,
    last-contribution: uint
  }
)

;; Monthly leaderboards
(define-map monthly-leaderboard
  { month: uint, year: uint, rank: uint }
  {
    user: principal,
    score: uint,
    category: uint
  }
)

;; Yearly leaderboards
(define-map yearly-leaderboard
  { year: uint, rank: uint }
  {
    user: principal,
    score: uint,
    category: uint
  }
)

;; Category metadata
(define-map category-info
  { category: uint }
  {
    name: (string-ascii 50),
    unit: (string-ascii 20),
    multiplier: uint
  }
)

;; Reward history
(define-map reward-history
  { user: principal, period: uint, period-type: (string-ascii 10) }
  {
    amount: uint,
    rank: uint,
    category: uint,
    timestamp: uint
  }
)

;; Initialize categories
(map-set category-info { category: CATEGORY_TREES_PLANTED }
  { name: "Trees Planted", unit: "trees", multiplier: u10 })
(map-set category-info { category: CATEGORY_RECYCLING }
  { name: "Recycling Actions", unit: "items", multiplier: u5 })
(map-set category-info { category: CATEGORY_ENERGY_SAVED }
  { name: "Energy Saved", unit: "kWh", multiplier: u2 })
(map-set category-info { category: CATEGORY_WATER_CONSERVED }
  { name: "Water Conserved", unit: "liters", multiplier: u1 })
(map-set category-info { category: CATEGORY_CARBON_REDUCED }
  { name: "Carbon Reduced", unit: "kg CO2", multiplier: u3 })

;; Private Functions

(define-private (is-valid-category (category uint))
  (and (>= category u1) (<= category u5))
)

(define-private (calculate-score (amount uint) (category uint))
  (let ((multiplier (default-to u1 (get multiplier (map-get? category-info { category: category })))))
    (* amount multiplier)
  )
)

(define-private (get-current-timestamp)
  stacks-block-height
)

;; Public Functions

;; Register a new user
(define-public (register-user)
  (let ((user tx-sender))
    (if (is-none (map-get? users { user: user }))
      (begin
        (map-set users { user: user }
          {
            total-score: u0,
            monthly-score: u0,
            yearly-score: u0,
            last-activity: (get-current-timestamp),
            rewards-earned: u0
          }
        )
        (var-set total-users (+ (var-get total-users) u1))
        (ok true)
      )
      (ok false) ;; User already registered
    )
  )
)

;; Record an eco-friendly action
(define-public (record-action (category uint) (amount uint))
  (let (
    (user tx-sender)
    (timestamp (get-current-timestamp))
    (score (calculate-score amount category))
  )
    (asserts! (is-valid-category category) ERR_INVALID_CATEGORY)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Ensure user is registered
    (unwrap!  (register-user) (err u105))
    
    ;; Update user's overall scores
    (let ((user-data (unwrap! (map-get? users { user: user }) ERR_USER_NOT_FOUND)))
      (map-set users { user: user }
        {
          total-score: (+ (get total-score user-data) score),
          monthly-score: (+ (get monthly-score user-data) score),
          yearly-score: (+ (get yearly-score user-data) score),
          last-activity: timestamp,
          rewards-earned: (get rewards-earned user-data)
        }
      )
    )
    
    ;; Update category-specific contributions
    (let ((category-data (default-to 
      { total-amount: u0, monthly-amount: u0, yearly-amount: u0, last-contribution: u0 }
      (map-get? user-category-contributions { user: user, category: category }))))
      (map-set user-category-contributions { user: user, category: category }
        {
          total-amount: (+ (get total-amount category-data) amount),
          monthly-amount: (+ (get monthly-amount category-data) amount),
          yearly-amount: (+ (get yearly-amount category-data) amount),
          last-contribution: timestamp
        }
      )
    )
    
    (ok score)
  )
)

;; Reset monthly scores (called at the beginning of each month)
(define-public (reset-monthly-scores)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set current-month (+ (var-get current-month) u1))
    ;; Note: In a real implementation, you'd iterate through all users
    ;; This is a simplified version
    (ok true)
  )
)

;; Reset yearly scores (called at the beginning of each year)
(define-public (reset-yearly-scores)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set current-year (+ (var-get current-year) u1))
    (var-set current-month u1)
    ;; Note: In a real implementation, you'd iterate through all users
    ;; This is a simplified version
    (ok true)
  )
)

;; Distribute monthly rewards to top contributors
(define-public (distribute-monthly-rewards (winners (list 10 principal)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (let ((reward-per-winner (/ MONTHLY_TOP_REWARD (len winners))))
      (begin
        (fold distribute-reward-fold winners reward-per-winner)
        (ok true)
      )
    )
  )
)

;; Distribute yearly rewards to top contributors
(define-public (distribute-yearly-rewards (winners (list 10 principal)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (let ((reward-per-winner (/ YEARLY_TOP_REWARD (len winners))))
      (begin
        (fold distribute-reward-fold winners reward-per-winner)
        (ok true)
      )
    )
  )
)

;; Helper function to distribute rewards
(define-private (distribute-reward-to-user (user principal) (amount uint))
  (let ((user-data (default-to 
    { total-score: u0, monthly-score: u0, yearly-score: u0, last-activity: u0, rewards-earned: u0 }
    (map-get? users { user: user }))))
    (map-set users { user: user }
      (merge user-data { rewards-earned: (+ (get rewards-earned user-data) amount) })
    )
    true
  )
)

;; Helper function for fold to distribute rewards
(define-private (distribute-reward-fold (user principal) (amount uint))
  (begin
    (distribute-reward-to-user user amount)
    amount
  )
)

;; Claim rewards
(define-public (claim-rewards)
  (let (
    (user tx-sender)
    (user-data (unwrap! (map-get? users { user: user }) ERR_USER_NOT_FOUND))
    (rewards (get rewards-earned user-data))
  )
    (asserts! (> rewards u0) ERR_INSUFFICIENT_BALANCE)
    
    ;; Reset user's reward balance
    (map-set users { user: user }
      (merge user-data { rewards-earned: u0 })
    )
    
    ;; Transfer rewards to user
    (as-contract (stx-transfer? rewards tx-sender user))
  )
)

;; Read-only Functions

;; Get user profile
(define-read-only (get-user-profile (user principal))
  (map-get? users { user: user })
)

;; Get user's category contributions
(define-read-only (get-user-category-stats (user principal) (category uint))
  (map-get? user-category-contributions { user: user, category: category })
)

;; Get category information
(define-read-only (get-category-info (category uint))
  (map-get? category-info { category: category })
)

;; Get total number of users
(define-read-only (get-total-users)
  (var-get total-users)
)

;; Get current period information
(define-read-only (get-current-period)
  {
    month: (var-get current-month),
    year: (var-get current-year)
  }
)

;; Get monthly leaderboard entry
(define-read-only (get-monthly-leaderboard-entry (month uint) (year uint) (rank uint))
  (map-get? monthly-leaderboard { month: month, year: year, rank: rank })
)

;; Get yearly leaderboard entry
(define-read-only (get-yearly-leaderboard-entry (year uint) (rank uint))
  (map-get? yearly-leaderboard { year: year, rank: rank })
)

;; Check if user exists
(define-read-only (user-exists (user principal))
  (is-some (map-get? users { user: user }))
)

;; Get user's rank in a specific category (simplified - returns mock data)
(define-read-only (get-user-rank (user principal) (category uint))
  (if (user-exists user)
    (some u1) ;; In a real implementation, this would calculate actual rank
    none
  )
)
