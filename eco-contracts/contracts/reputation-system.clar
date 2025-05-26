;; Eco-Action Reputation System Smart Contract
;; Manages user reputation scores, badges, and achievements

;; ===== CONSTANTS =====
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-reputation (err u103))
(define-constant err-invalid-parameters (err u104))

;; Reputation point values for different actions
(define-constant points-recycling u10)
(define-constant points-energy-saving u15)
(define-constant points-carbon-reduction u20)
(define-constant points-water-conservation u12)
(define-constant points-sustainable-transport u18)

;; Badge requirement thresholds
(define-constant badge-beginner-threshold u50)
(define-constant badge-intermediate-threshold u200)
(define-constant badge-advanced-threshold u500)
(define-constant badge-expert-threshold u1000)

;; ===== DATA STRUCTURES =====

;; User reputation data
(define-map user-reputation
  { user: principal }
  {
    total-points: uint,
    verified-actions: uint,
    reliability-score: uint, ;; Out of 100
    last-updated: uint,
    created-at: uint
  }
)

;; Badge definitions
(define-map badges
  { badge-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    icon: (string-ascii 100),
    requirement-type: (string-ascii 20), ;; "points", "actions", "specific"
    requirement-value: uint,
    is-active: bool,
    created-at: uint
  }
)

;; User badges (many-to-many relationship)
(define-map user-badges
  { user: principal, badge-id: uint }
  {
    earned-at: uint,
    verified-by: (optional principal)
  }
)

;; Achievement tracking
(define-map achievements
  { achievement-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    category: (string-ascii 30),
    points-reward: uint,
    requirements: (string-ascii 300),
    is-active: bool
  }
)

;; User achievement progress
(define-map user-achievements
  { user: principal, achievement-id: uint }
  {
    progress: uint,
    completed: bool,
    completed-at: (optional uint)
  }
)

;; Action categories for reputation tracking
(define-map action-categories
  { category-id: uint }
  {
    name: (string-ascii 30),
    points-per-action: uint,
    reliability-weight: uint ;; How much this action affects reliability score
  }
)

;; Counter for IDs
(define-data-var next-badge-id uint u1)
(define-data-var next-achievement-id uint u1)
(define-data-var next-category-id uint u1)

;; ===== INITIALIZATION =====

;; Initialize default action categories
(map-set action-categories { category-id: u1 } 
  { name: "recycling", points-per-action: points-recycling, reliability-weight: u5 })
(map-set action-categories { category-id: u2 } 
  { name: "energy-saving", points-per-action: points-energy-saving, reliability-weight: u7 })
(map-set action-categories { category-id: u3 } 
  { name: "carbon-reduction", points-per-action: points-carbon-reduction, reliability-weight: u10 })
(map-set action-categories { category-id: u4 } 
  { name: "water-conservation", points-per-action: points-water-conservation, reliability-weight: u6 })
(map-set action-categories { category-id: u5 } 
  { name: "sustainable-transport", points-per-action: points-sustainable-transport, reliability-weight: u8 })

;; Set initial counter values
(var-set next-category-id u6)

;; ===== REPUTATION MANAGEMENT =====

;; Initialize user reputation
(define-public (initialize-user-reputation (user principal))
  (begin
    (asserts! (is-none (map-get? user-reputation { user: user })) err-already-exists)
    (ok (map-set user-reputation { user: user }
      {
        total-points: u0,
        verified-actions: u0,
        reliability-score: u50, ;; Start with neutral reliability
        last-updated: stacks-block-height,
        created-at: stacks-block-height
      }))
  )
)

;; Add reputation points for verified eco-action
(define-public (add-reputation-points (user principal) (category-id uint) (multiplier uint))
  (let (
    (category (unwrap! (map-get? action-categories { category-id: category-id }) err-not-found))
    (current-rep (default-to 
      { total-points: u0, verified-actions: u0, reliability-score: u50, last-updated: u0, created-at: stacks-block-height }
      (map-get? user-reputation { user: user })))
    (points-to-add (* (get points-per-action category) multiplier))
    (new-total-points (+ (get total-points current-rep) points-to-add))
    (new-verified-actions (+ (get verified-actions current-rep) u1))
    (reliability-boost (get reliability-weight category))
    (new-reliability (+ (get reliability-score current-rep) reliability-boost))
  )
    (map-set user-reputation { user: user }
      {
        total-points: new-total-points,
        verified-actions: new-verified-actions,
        reliability-score: new-reliability,
        last-updated: stacks-block-height,
        created-at: (get created-at current-rep)
      })
    (ok new-total-points)
  )
)

;; ===== BADGE SYSTEM =====

;; Create a new badge
(define-public (create-badge (name (string-ascii 50)) (description (string-ascii 200)) 
                           (icon (string-ascii 100)) (requirement-type (string-ascii 20)) 
                           (requirement-value uint))
  (let ((badge-id (var-get next-badge-id)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set badges { badge-id: badge-id }
      {
        name: name,
        description: description,
        icon: icon,
        requirement-type: requirement-type,
        requirement-value: requirement-value,
        is-active: true,
        created-at: stacks-block-height
      })
    (var-set next-badge-id (+ badge-id u1))
    (ok badge-id)
  )
)

;; Award badge to user
(define-public (award-badge (user principal) (badge-id uint))
  (let ((badge (unwrap! (map-get? badges { badge-id: badge-id }) err-not-found)))
    (asserts! (get is-active badge) err-not-found)
    (asserts! (is-none (map-get? user-badges { user: user, badge-id: badge-id })) err-already-exists)
    (ok (map-set user-badges { user: user, badge-id: badge-id }
      {
        earned-at: stacks-block-height,
        verified-by: (some tx-sender)
      }))
  )
)

;; Check and automatically award badges based on reputation
(define-private (check-and-award-badges (user principal) (total-points uint) (verified-actions uint))
  (begin
    ;; Award point-based badges
    (if (and (>= total-points badge-beginner-threshold) 
             (is-none (map-get? user-badges { user: user, badge-id: u1 })))
        (map-set user-badges { user: user, badge-id: u1 }
          { earned-at: stacks-block-height, verified-by: none })
        true)
    
    (if (and (>= total-points badge-intermediate-threshold) 
             (is-none (map-get? user-badges { user: user, badge-id: u2 })))
        (map-set user-badges { user: user, badge-id: u2 }
          { earned-at: stacks-block-height, verified-by: none })
        true)
    
    (if (and (>= total-points badge-advanced-threshold) 
             (is-none (map-get? user-badges { user: user, badge-id: u3 })))
        (map-set user-badges { user: user, badge-id: u3 }
          { earned-at: stacks-block-height, verified-by: none })
        true)
    
    (if (and (>= total-points badge-expert-threshold) 
             (is-none (map-get? user-badges { user: user, badge-id: u4 })))
        (map-set user-badges { user: user, badge-id: u4 }
          { earned-at: stacks-block-height, verified-by: none })
        true)
    
    (ok true)
  )
)

;; ===== ACHIEVEMENT SYSTEM =====

;; Create achievement
(define-public (create-achievement (name (string-ascii 50)) (description (string-ascii 200))
                                 (category (string-ascii 30)) (points-reward uint)
                                 (requirements (string-ascii 300)))
  (let ((achievement-id (var-get next-achievement-id)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set achievements { achievement-id: achievement-id }
      {
        name: name,
        description: description,
        category: category,
        points-reward: points-reward,
        requirements: requirements,
        is-active: true
      })
    (var-set next-achievement-id (+ achievement-id u1))
    (ok achievement-id)
  )
)

;; Update achievement progress
(define-public (update-achievement-progress (user principal) (achievement-id uint) (progress uint))
  (let (
    (achievement (unwrap! (map-get? achievements { achievement-id: achievement-id }) err-not-found))
    (current-progress (default-to 
      { progress: u0, completed: false, completed-at: none }
      (map-get? user-achievements { user: user, achievement-id: achievement-id })))
  )
    (asserts! (get is-active achievement) err-not-found)
    (if (>= progress u100) ;; Achievement completed
        (begin
          (map-set user-achievements { user: user, achievement-id: achievement-id }
            {
              progress: u100,
              completed: true,
              completed-at: (some stacks-block-height)
            })
          ;; Award points for completing achievement
          (try! (add-reputation-points user u1 (/ (get points-reward achievement) points-recycling)))
          (ok true))
        (begin
          (map-set user-achievements { user: user, achievement-id: achievement-id }
            {
              progress: progress,
              completed: false,
              completed-at: none
            })
          (ok false)))
  )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Get user reputation
(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation { user: user })
)

;; Get user's badges
(define-read-only (get-user-badge (user principal) (badge-id uint))
  (map-get? user-badges { user: user, badge-id: badge-id })
)

;; Get badge details
(define-read-only (get-badge (badge-id uint))
  (map-get? badges { badge-id: badge-id })
)

;; Get achievement details
(define-read-only (get-achievement (achievement-id uint))
  (map-get? achievements { achievement-id: achievement-id })
)

;; Get user achievement progress
(define-read-only (get-user-achievement-progress (user principal) (achievement-id uint))
  (map-get? user-achievements { user: user, achievement-id: achievement-id })
)

;; Get action category
(define-read-only (get-action-category (category-id uint))
  (map-get? action-categories { category-id: category-id })
)

;; Get leaderboard position (simplified - returns user's rank based on points)
(define-read-only (get-user-rank (user principal))
  (match (map-get? user-reputation { user: user })
    reputation (get total-points reputation)
    u0
  )
)

;; ===== ADMIN FUNCTIONS =====

;; Deactivate badge
(define-public (deactivate-badge (badge-id uint))
  (let ((badge (unwrap! (map-get? badges { badge-id: badge-id }) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set badges { badge-id: badge-id }
      (merge badge { is-active: false })))
  )
)

;; Deactivate achievement
(define-public (deactivate-achievement (achievement-id uint))
  (let ((achievement (unwrap! (map-get? achievements { achievement-id: achievement-id }) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set achievements { achievement-id: achievement-id }
      (merge achievement { is-active: false })))
  )
)

;; Initialize default badges
(define-private (init-default-badges)
  (begin
    (map-set badges { badge-id: u1 }
      {
        name: "Eco Starter",
        description: "Earned your first 50 reputation points",
        icon: "starter-badge.svg",
        requirement-type: "points",
        requirement-value: badge-beginner-threshold,
        is-active: true,
        created-at: stacks-block-height
      })
    (map-set badges { badge-id: u2 }
      {
        name: "Green Warrior",
        description: "Reached 200 reputation points",
        icon: "warrior-badge.svg",
        requirement-type: "points",
        requirement-value: badge-intermediate-threshold,
        is-active: true,
        created-at: stacks-block-height
      })
    (map-set badges { badge-id: u3 }
      {
        name: "Eco Champion",
        description: "Achieved 500 reputation points",
        icon: "champion-badge.svg",
        requirement-type: "points",
        requirement-value: badge-advanced-threshold,
        is-active: true,
        created-at: stacks-block-height
      })
    (map-set badges { badge-id: u4 }
      {
        name: "Planet Guardian",
        description: "Reached the prestigious 1000 reputation points",
        icon: "guardian-badge.svg",
        requirement-type: "points",
        requirement-value: badge-expert-threshold,
        is-active: true,
        created-at: stacks-block-height
      })
    (var-set next-badge-id u5)
  )
)
