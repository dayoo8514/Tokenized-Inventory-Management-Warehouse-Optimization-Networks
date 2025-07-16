;; Cost Reduction Contract
;; Monitors operational costs and incentivizes cost-saving initiatives

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-INPUT (err u501))
(define-constant ERR-INITIATIVE-NOT-FOUND (err u502))
(define-constant ERR-INSUFFICIENT-SAVINGS (err u503))
(define-constant ERR-ALREADY-CLAIMED (err u504))

;; Data Variables
(define-data-var next-initiative-id uint u1)
(define-data-var next-cost-record-id uint u1)
(define-data-var total-cost-savings uint u0)
(define-data-var reward-pool uint u100000)
(define-data-var min-savings-threshold uint u1000)

;; Data Maps
(define-map cost-reduction-initiatives uint {
    title: (string-ascii 100),
    description: (string-ascii 300),
    proposed-by: principal,
    category: (string-ascii 50),
    estimated-savings: uint,
    actual-savings: uint,
    implementation-cost: uint,
    roi-percentage: uint,
    status: (string-ascii 20),
    created-at: uint,
    implemented-at: uint,
    verified: bool
})

(define-map operational-costs uint {
    cost-category: (string-ascii 50),
    amount: uint,
    period: (string-ascii 20),
    recorded-by: principal,
    recorded-at: uint,
    cost-center: (string-ascii 50),
    is-recurring: bool
})

(define-map cost-savings-rewards principal {
    total-earned: uint,
    initiatives-count: uint,
    average-savings: uint,
    last-reward: uint,
    reward-multiplier: uint,
    performance-tier: (string-ascii 20)
})

(define-map monthly-cost-summary uint {
    month: uint,
    year: uint,
    total-costs: uint,
    total-savings: uint,
    net-reduction: uint,
    initiatives-implemented: uint,
    top-performer: principal
})

(define-map cost-categories (string-ascii 50) {
    category-name: (string-ascii 50),
    baseline-cost: uint,
    current-cost: uint,
    reduction-target: uint,
    achieved-reduction: uint,
    last-updated: uint
})

;; Private Functions
(define-private (calculate-roi (savings uint) (cost uint))
    (if (> cost u0)
        (/ (* (- savings cost) u100) cost)
        u0
    )
)

(define-private (calculate-reward-amount (savings uint) (multiplier uint))
    (/ (* savings multiplier) u100)
)

(define-private (get-performance-tier (total-savings uint))
    (if (>= total-savings u50000)
        "platinum"
        (if (>= total-savings u25000)
            "gold"
            (if (>= total-savings u10000)
                "silver"
                "bronze"
            )
        )
    )
)

;; Public Functions

;; Submit cost reduction initiative
(define-public (submit-cost-initiative (title (string-ascii 100)) (description (string-ascii 300))
                                      (category (string-ascii 50)) (estimated-savings uint) (implementation-cost uint))
    (let (
        (initiative-id (var-get next-initiative-id))
        (roi (calculate-roi estimated-savings implementation-cost))
    )
        (asserts! (> estimated-savings u0) ERR-INVALID-INPUT)
        (asserts! (>= estimated-savings (var-get min-savings-threshold)) ERR-INSUFFICIENT-SAVINGS)

        (map-set cost-reduction-initiatives initiative-id {
            title: title,
            description: description,
            proposed-by: tx-sender,
            category: category,
            estimated-savings: estimated-savings,
            actual-savings: u0,
            implementation-cost: implementation-cost,
            roi-percentage: roi,
            status: "proposed",
            created-at: block-height,
            implemented-at: u0,
            verified: false
        })

        (var-set next-initiative-id (+ initiative-id u1))
        (ok initiative-id)
    )
)

;; Approve and implement initiative (only contract owner)
(define-public (approve-initiative (initiative-id uint))
    (let (
        (initiative (unwrap! (map-get? cost-reduction-initiatives initiative-id) ERR-INITIATIVE-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status initiative) "proposed") ERR-NOT-AUTHORIZED)

        (map-set cost-reduction-initiatives initiative-id (merge initiative {
            status: "approved",
            implemented-at: block-height
        }))

        (ok true)
    )
)

;; Record actual cost savings
(define-public (record-actual-savings (initiative-id uint) (actual-savings uint))
    (let (
        (initiative (unwrap! (map-get? cost-reduction-initiatives initiative-id) ERR-INITIATIVE-NOT-FOUND))
        (proposer (get proposed-by initiative))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status initiative) "approved") ERR-NOT-AUTHORIZED)
        (asserts! (> actual-savings u0) ERR-INVALID-INPUT)

        (let (
            (new-roi (calculate-roi actual-savings (get implementation-cost initiative)))
        )
            (map-set cost-reduction-initiatives initiative-id (merge initiative {
                actual-savings: actual-savings,
                roi-percentage: new-roi,
                status: "completed",
                verified: true
            }))

            ;; Update global savings
            (var-set total-cost-savings (+ (var-get total-cost-savings) actual-savings))

            ;; Award rewards to proposer
            (award-cost-reduction-reward proposer actual-savings)

            (ok new-roi)
        )
    )
)

;; Record operational cost
(define-public (record-operational-cost (category (string-ascii 50)) (amount uint) (period (string-ascii 20))
                                       (cost-center (string-ascii 50)) (is-recurring bool))
    (let (
        (cost-record-id (var-get next-cost-record-id))
    )
        (asserts! (> amount u0) ERR-INVALID-INPUT)

        (map-set operational-costs cost-record-id {
            cost-category: category,
            amount: amount,
            period: period,
            recorded-by: tx-sender,
            recorded-at: block-height,
            cost-center: cost-center,
            is-recurring: is-recurring
        })

        ;; Update cost category baseline if it exists
        (update-cost-category-baseline category amount)

        (var-set next-cost-record-id (+ cost-record-id u1))
        (ok cost-record-id)
    )
)

;; Update cost category baseline
(define-private (update-cost-category-baseline (category (string-ascii 50)) (new-cost uint))
    (let (
        (current-category (default-to {
            category-name: category,
            baseline-cost: new-cost,
            current-cost: new-cost,
            reduction-target: u0,
            achieved-reduction: u0,
            last-updated: block-height
        } (map-get? cost-categories category)))
    )
        (map-set cost-categories category (merge current-category {
            current-cost: new-cost,
            last-updated: block-height
        }))
    )
)

;; Award cost reduction reward
(define-private (award-cost-reduction-reward (recipient principal) (savings uint))
    (let (
        (current-rewards (default-to {
            total-earned: u0,
            initiatives-count: u0,
            average-savings: u0,
            last-reward: u0,
            reward-multiplier: u5,
            performance-tier: "bronze"
        } (map-get? cost-savings-rewards recipient)))
        (new-initiatives (+ (get initiatives-count current-rewards) u1))
        (new-total-earned (+ (get total-earned current-rewards) savings))
        (new-avg-savings (/ new-total-earned new-initiatives))
        (reward-amount (calculate-reward-amount savings (get reward-multiplier current-rewards)))
        (new-tier (get-performance-tier new-total-earned))
        (new-multiplier (if (is-eq new-tier "platinum") u10
                          (if (is-eq new-tier "gold") u8
                            (if (is-eq new-tier "silver") u6 u5))))
    )
        (map-set cost-savings-rewards recipient {
            total-earned: new-total-earned,
            initiatives-count: new-initiatives,
            average-savings: new-avg-savings,
            last-reward: reward-amount,
            reward-multiplier: new-multiplier,
            performance-tier: new-tier
        })

        ;; Deduct from reward pool
        (if (>= (var-get reward-pool) reward-amount)
            (var-set reward-pool (- (var-get reward-pool) reward-amount))
            (var-set reward-pool u0)
        )
    )
)

;; Set cost reduction target for category
(define-public (set-cost-reduction-target (category (string-ascii 50)) (target-reduction uint))
    (let (
        (current-category (unwrap! (map-get? cost-categories category) ERR-INVALID-INPUT))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> target-reduction u0) ERR-INVALID-INPUT)

        (map-set cost-categories category (merge current-category {
            reduction-target: target-reduction,
            last-updated: block-height
        }))

        (ok true)
    )
)

;; Generate monthly cost summary
(define-public (generate-monthly-summary (month uint) (year uint) (total-costs uint)
                                        (total-savings uint) (initiatives-count uint) (top-performer principal))
    (let (
        (summary-id (+ (* year u100) month))
        (net-reduction (if (>= total-savings total-costs) (- total-savings total-costs) u0))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= month u1) (<= month u12)) ERR-INVALID-INPUT)

        (map-set monthly-cost-summary summary-id {
            month: month,
            year: year,
            total-costs: total-costs,
            total-savings: total-savings,
            net-reduction: net-reduction,
            initiatives-implemented: initiatives-count,
            top-performer: top-performer
        })

        (ok summary-id)
    )
)

;; Claim cost reduction reward
(define-public (claim-cost-reduction-reward (initiative-id uint))
    (let (
        (initiative (unwrap! (map-get? cost-reduction-initiatives initiative-id) ERR-INITIATIVE-NOT-FOUND))
        (proposer (get proposed-by initiative))
    )
        (asserts! (is-eq tx-sender proposer) ERR-NOT-AUTHORIZED)
        (asserts! (get verified initiative) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status initiative) "completed") ERR-NOT-AUTHORIZED)

        ;; Additional reward claiming logic would go here
        (ok (get actual-savings initiative))
    )
)

;; Read-only functions
(define-read-only (get-cost-initiative (initiative-id uint))
    (map-get? cost-reduction-initiatives initiative-id)
)

(define-read-only (get-operational-cost (cost-record-id uint))
    (map-get? operational-costs cost-record-id)
)

(define-read-only (get-cost-savings-rewards (user principal))
    (map-get? cost-savings-rewards user)
)

(define-read-only (get-monthly-summary (summary-id uint))
    (map-get? monthly-cost-summary summary-id)
)

(define-read-only (get-cost-category (category (string-ascii 50)))
    (map-get? cost-categories category)
)

(define-read-only (get-global-cost-stats)
    {
        total-savings: (var-get total-cost-savings),
        reward-pool: (var-get reward-pool),
        min-threshold: (var-get min-savings-threshold),
        next-initiative-id: (var-get next-initiative-id),
        next-cost-record-id: (var-get next-cost-record-id)
    }
)

(define-read-only (calculate-initiative-roi (savings uint) (cost uint))
    (calculate-roi savings cost)
)
