;; Layout Optimization Contract
;; Manages warehouse layout configurations and optimization proposals

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-DIMENSIONS (err u201))
(define-constant ERR-INVALID-EFFICIENCY (err u202))
(define-constant ERR-LAYOUT-NOT-FOUND (err u203))
(define-constant ERR-PROPOSAL-EXISTS (err u204))

;; Data Variables
(define-data-var next-layout-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var min-efficiency-threshold uint u70)

;; Data Maps
(define-map warehouse-layouts uint {
    width: uint,
    height: uint,
    zones: uint,
    efficiency-score: uint,
    created-by: principal,
    created-at: uint,
    is-active: bool
})

(define-map layout-proposals uint {
    layout-id: uint,
    proposed-by: principal,
    width: uint,
    height: uint,
    zones: uint,
    estimated-efficiency: uint,
    proposal-time: uint,
    status: (string-ascii 20),
    votes-for: uint,
    votes-against: uint
})

(define-map zone-configurations uint {
    layout-id: uint,
    zone-id: uint,
    zone-type: (string-ascii 30),
    x-position: uint,
    y-position: uint,
    width: uint,
    height: uint,
    capacity: uint
})

(define-map layout-metrics uint {
    layout-id: uint,
    picking-distance: uint,
    storage-utilization: uint,
    throughput-capacity: uint,
    maintenance-cost: uint,
    last-updated: uint
})

;; Private Functions
(define-private (calculate-layout-efficiency (width uint) (height uint) (zones uint))
    (let (
        (area (* width height))
        (zone-density (/ (* zones u100) area))
        (base-efficiency u60)
    )
        (if (<= zone-density u20)
            (+ base-efficiency u20)
            (if (<= zone-density u40)
                (+ base-efficiency u10)
                base-efficiency
            )
        )
    )
)

(define-private (is-valid-dimensions (width uint) (height uint))
    (and (> width u0) (> height u0) (<= width u1000) (<= height u1000))
)

;; Public Functions

;; Create new warehouse layout
(define-public (create-layout (width uint) (height uint) (zones uint))
    (let (
        (layout-id (var-get next-layout-id))
        (efficiency (calculate-layout-efficiency width height zones))
    )
        (asserts! (is-valid-dimensions width height) ERR-INVALID-DIMENSIONS)
        (asserts! (> zones u0) ERR-INVALID-DIMENSIONS)

        (map-set warehouse-layouts layout-id {
            width: width,
            height: height,
            zones: zones,
            efficiency-score: efficiency,
            created-by: tx-sender,
            created-at: block-height,
            is-active: true
        })

        (map-set layout-metrics layout-id {
            layout-id: layout-id,
            picking-distance: u0,
            storage-utilization: u0,
            throughput-capacity: u0,
            maintenance-cost: u0,
            last-updated: block-height
        })

        (var-set next-layout-id (+ layout-id u1))
        (ok layout-id)
    )
)

;; Submit layout optimization proposal
(define-public (submit-layout-proposal (layout-id uint) (new-width uint) (new-height uint) (new-zones uint))
    (let (
        (proposal-id (var-get next-proposal-id))
        (layout (unwrap! (map-get? warehouse-layouts layout-id) ERR-LAYOUT-NOT-FOUND))
        (estimated-efficiency (calculate-layout-efficiency new-width new-height new-zones))
    )
        (asserts! (is-valid-dimensions new-width new-height) ERR-INVALID-DIMENSIONS)
        (asserts! (> new-zones u0) ERR-INVALID-DIMENSIONS)
        (asserts! (>= estimated-efficiency (var-get min-efficiency-threshold)) ERR-INVALID-EFFICIENCY)

        (map-set layout-proposals proposal-id {
            layout-id: layout-id,
            proposed-by: tx-sender,
            width: new-width,
            height: new-height,
            zones: new-zones,
            estimated-efficiency: estimated-efficiency,
            proposal-time: block-height,
            status: "pending",
            votes-for: u0,
            votes-against: u0
        })

        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

;; Vote on layout proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
    (let (
        (proposal (unwrap! (map-get? layout-proposals proposal-id) ERR-LAYOUT-NOT-FOUND))
    )
        (asserts! (is-eq (get status proposal) "pending") ERR-NOT-AUTHORIZED)

        (if vote-for
            (map-set layout-proposals proposal-id (merge proposal {
                votes-for: (+ (get votes-for proposal) u1)
            }))
            (map-set layout-proposals proposal-id (merge proposal {
                votes-against: (+ (get votes-against proposal) u1)
            }))
        )

        (ok true)
    )
)

;; Approve layout proposal (only contract owner)
(define-public (approve-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? layout-proposals proposal-id) ERR-LAYOUT-NOT-FOUND))
        (layout-id (get layout-id proposal))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status proposal) "pending") ERR-NOT-AUTHORIZED)

        ;; Update the layout with new configuration
        (map-set warehouse-layouts layout-id {
            width: (get width proposal),
            height: (get height proposal),
            zones: (get zones proposal),
            efficiency-score: (get estimated-efficiency proposal),
            created-by: (get proposed-by proposal),
            created-at: block-height,
            is-active: true
        })

        (map-set layout-proposals proposal-id (merge proposal {
            status: "approved"
        }))

        (ok true)
    )
)

;; Configure zone in layout
(define-public (configure-zone (layout-id uint) (zone-id uint) (zone-type (string-ascii 30))
                              (x-pos uint) (y-pos uint) (zone-width uint) (zone-height uint) (capacity uint))
    (let (
        (layout (unwrap! (map-get? warehouse-layouts layout-id) ERR-LAYOUT-NOT-FOUND))
    )
        (asserts! (is-eq (get created-by layout) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (< zone-id (get zones layout)) ERR-INVALID-DIMENSIONS)

        (map-set zone-configurations zone-id {
            layout-id: layout-id,
            zone-id: zone-id,
            zone-type: zone-type,
            x-position: x-pos,
            y-position: y-pos,
            width: zone-width,
            height: zone-height,
            capacity: capacity
        })

        (ok true)
    )
)

;; Update layout metrics
(define-public (update-layout-metrics (layout-id uint) (picking-distance uint)
                                     (storage-util uint) (throughput uint) (maintenance uint))
    (let (
        (layout (unwrap! (map-get? warehouse-layouts layout-id) ERR-LAYOUT-NOT-FOUND))
    )
        (map-set layout-metrics layout-id {
            layout-id: layout-id,
            picking-distance: picking-distance,
            storage-utilization: storage-util,
            throughput-capacity: throughput,
            maintenance-cost: maintenance,
            last-updated: block-height
        })

        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-layout (layout-id uint))
    (map-get? warehouse-layouts layout-id)
)

(define-read-only (get-layout-proposal (proposal-id uint))
    (map-get? layout-proposals proposal-id)
)

(define-read-only (get-zone-configuration (zone-id uint))
    (map-get? zone-configurations zone-id)
)

(define-read-only (get-layout-metrics (layout-id uint))
    (map-get? layout-metrics layout-id)
)

(define-read-only (calculate-efficiency-score (width uint) (height uint) (zones uint))
    (calculate-layout-efficiency width height zones)
)
