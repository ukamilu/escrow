(define-map escrows uint { buyer: principal, seller: principal, arbitrator: principal, amount: uint, state: uint, created-at: uint, timeout-blocks: uint })
(define-map timeout-extensions uint { proposed-timeout: uint, buyer-approved: bool, seller-approved: bool })
;; states: 0 = funded, 1 = released, 2 = disputed, 3 = expired

;; Error codes
(define-constant ERR-NOT-FOUND u1)
(define-constant ERR-ALREADY-EXISTS u2)
(define-constant ERR-INVALID-STATE u3)
(define-constant ERR-UNAUTHORIZED u4)
(define-constant ERR-INVALID-AMOUNT u5)
(define-constant ERR-INVALID-PRINCIPAL u6)
(define-constant ERR-INVALID-ID u7)
(define-constant ERR-NOT-EXPIRED u8)
(define-constant ERR-INVALID-TIMEOUT u9)

;; Constants for validation
(define-constant MIN-AMOUNT u1000000) ;; Minimum 1 STX in microSTX
(define-constant MAX-AMOUNT u1000000000000) ;; Maximum amount
(define-constant MAX-ESCROW-ID u999999999) ;; Maximum escrow ID
(define-constant MIN-TIMEOUT-BLOCKS u144) ;; Minimum 1 day (144 blocks)
(define-constant MAX-TIMEOUT-BLOCKS u52560) ;; Maximum ~1 year (52560 blocks)
(define-constant DEFAULT-TIMEOUT-BLOCKS u4320) ;; Default 30 days

;; Input validation functions
(define-private (is-valid-principal (p principal))
  (not (is-eq p tx-sender))) ;; Prevent self-transactions

(define-private (is-valid-amount (amount uint))
  (and (>= amount MIN-AMOUNT) (<= amount MAX-AMOUNT)))

(define-private (is-valid-id (id uint))
  (and (> id u0) (<= id MAX-ESCROW-ID)))

(define-private (is-valid-timeout (timeout uint))
  (and (>= timeout MIN-TIMEOUT-BLOCKS) (<= timeout MAX-TIMEOUT-BLOCKS)))

(define-private (is-escrow-expired (escrow-data {buyer: principal, seller: principal, arbitrator: principal, amount: uint, state: uint, created-at: uint, timeout-blocks: uint}))
  (> stacks-block-height (+ (get created-at escrow-data) (get timeout-blocks escrow-data))))

(define-private (is-timeout-adjustable (escrow-data {buyer: principal, seller: principal, arbitrator: principal, amount: uint, state: uint, created-at: uint, timeout-blocks: uint}))
  (or (is-eq (get state escrow-data) u0) (is-eq (get state escrow-data) u2)))

(define-private (update-escrow (id uint) (current {buyer: principal, seller: principal, arbitrator: principal, amount: uint, state: uint, created-at: uint, timeout-blocks: uint}) (new-state (optional uint)) (new-timeout (optional uint)))
  (map-set escrows id {
    buyer: (get buyer current),
    seller: (get seller current),
    arbitrator: (get arbitrator current),
    amount: (get amount current),
    state: (default-to (get state current) new-state),
    created-at: (get created-at current),
    timeout-blocks: (default-to (get timeout-blocks current) new-timeout)
  }))

;; Enhanced create-escrow with optional timeout parameter
(define-public (create-escrow (id uint) (seller principal) (arb principal) (amount uint))
  (create-escrow-with-timeout id seller arb amount DEFAULT-TIMEOUT-BLOCKS))

;; New function with timeout parameter
(define-public (create-escrow-with-timeout (id uint) (seller principal) (arb principal) (amount uint) (timeout-blocks uint))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    (asserts! (is-valid-amount amount) (err ERR-INVALID-AMOUNT))
    (asserts! (is-valid-principal seller) (err ERR-INVALID-PRINCIPAL))
    (asserts! (is-valid-principal arb) (err ERR-INVALID-PRINCIPAL))
    (asserts! (is-valid-timeout timeout-blocks) (err ERR-INVALID-TIMEOUT))
    (asserts! (not (is-eq seller arb)) (err ERR-INVALID-PRINCIPAL))
    (asserts! (not (is-eq tx-sender seller)) (err ERR-INVALID-PRINCIPAL))
    (asserts! (not (is-eq tx-sender arb)) (err ERR-INVALID-PRINCIPAL))
    
    ;; Check if escrow ID already exists
    (asserts! (is-none (map-get? escrows id)) (err ERR-ALREADY-EXISTS))
    
    ;; Transfer funds from buyer to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Create escrow record with timeout information
    (map-set escrows id { 
      buyer: tx-sender, 
      seller: seller, 
      arbitrator: arb, 
      amount: amount, 
      state: u0,
      created-at: stacks-block-height,
      timeout-blocks: timeout-blocks
    })
    (ok true)))

(define-public (release (id uint))
  (begin
    ;; Validate input
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    
    (match (map-get? escrows id)
      val
        (begin
          ;; Check if escrow is in funded state
          (asserts! (is-eq (get state val) u0) (err ERR-INVALID-STATE))
          ;; Only buyer can release funds
          (asserts! (is-eq tx-sender (get buyer val)) (err ERR-UNAUTHORIZED))
          ;; Transfer funds from contract to seller
          (try! (as-contract (stx-transfer? (get amount val) tx-sender (get seller val))))
          ;; Update escrow state to released
          (update-escrow id val (some u1) none)
          (ok true))
      (err ERR-NOT-FOUND))))

(define-public (dispute (id uint))
  (begin
    ;; Validate input
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    
    (let ((e (map-get? escrows id)))
      (match e
        val
          (begin
            ;; Check if escrow is in funded state
            (asserts! (is-eq (get state val) u0) (err ERR-INVALID-STATE))
            ;; Only buyer or seller can initiate dispute
            (asserts! (or (is-eq tx-sender (get buyer val)) 
                         (is-eq tx-sender (get seller val))) 
                     (err ERR-UNAUTHORIZED))
            ;; Update escrow state to disputed
            (update-escrow id val (some u2) none)
            (ok true))
        (err ERR-NOT-FOUND)))))

(define-public (resolve-dispute (id uint) (release-to-seller bool))
  (begin
    ;; Validate input
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    
    (let ((e (map-get? escrows id)))
      (match e
        val
          (begin
            ;; Check if escrow is in disputed state
            (asserts! (is-eq (get state val) u2) (err ERR-INVALID-STATE))
            ;; Only arbitrator can resolve disputes
            (asserts! (is-eq tx-sender (get arbitrator val)) (err ERR-UNAUTHORIZED))
            ;; Transfer funds to appropriate party
            (if release-to-seller
              (try! (as-contract (stx-transfer? (get amount val) tx-sender (get seller val))))
              (try! (as-contract (stx-transfer? (get amount val) tx-sender (get buyer val)))))
            ;; Update escrow state to released
            (update-escrow id val (some u1) none)
            (ok true))
        (err ERR-NOT-FOUND)))))

;; New function: Handle expired escrows
(define-public (claim-expired (id uint))
  (begin
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    
    (let ((e (map-get? escrows id)))
      (match e
        val
          (begin
            ;; Check if escrow is in funded state and expired
            (asserts! (is-eq (get state val) u0) (err ERR-INVALID-STATE))
            (asserts! (is-escrow-expired val) (err ERR-NOT-EXPIRED))
            ;; Only buyer can claim expired funds
            (asserts! (is-eq tx-sender (get buyer val)) (err ERR-UNAUTHORIZED))
            ;; Refund to buyer
            (try! (as-contract (stx-transfer? (get amount val) tx-sender (get buyer val))))
            ;; Update state to expired
            (update-escrow id val (some u3) none)
            (ok true))
        (err ERR-NOT-FOUND)))))

;; Timeout extension workflow
(define-public (propose-timeout-extension (id uint) (new-timeout uint))
  (begin
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    (asserts! (is-valid-timeout new-timeout) (err ERR-INVALID-TIMEOUT))
    (let ((e (map-get? escrows id)))
      (match e
        escrow
          (let (
                (is-buyer (is-eq tx-sender (get buyer escrow)))
                (is-seller (is-eq tx-sender (get seller escrow)))
               )
            (asserts! (or is-buyer is-seller) (err ERR-UNAUTHORIZED))
            (asserts! (is-timeout-adjustable escrow) (err ERR-INVALID-STATE))
            (asserts! (> new-timeout (get timeout-blocks escrow)) (err ERR-INVALID-TIMEOUT))
            (map-set timeout-extensions id {
              proposed-timeout: new-timeout,
              buyer-approved: is-buyer,
              seller-approved: is-seller
            })
            (ok true))
        (err ERR-NOT-FOUND)))))

(define-public (approve-timeout-extension (id uint))
  (begin
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    (match (map-get? escrows id)
      escrow
        (begin
          (asserts! (is-timeout-adjustable escrow) (err ERR-INVALID-STATE))
          (match (map-get? timeout-extensions id)
            ext
              (let (
                    (is-buyer (is-eq tx-sender (get buyer escrow)))
                    (is-seller (is-eq tx-sender (get seller escrow)))
                   )
                (asserts! (or is-buyer is-seller) (err ERR-UNAUTHORIZED))
                (let (
                      (next-buyer (or (get buyer-approved ext) is-buyer))
                      (next-seller (or (get seller-approved ext) is-seller))
                     )
                  (map-set timeout-extensions id {
                    proposed-timeout: (get proposed-timeout ext),
                    buyer-approved: next-buyer,
                    seller-approved: next-seller
                  })
                  (if (and next-buyer next-seller)
                    (begin
                      (update-escrow id escrow none (some (get proposed-timeout ext)))
                      (map-delete timeout-extensions id)
                      (ok true))
                    (ok true))))
            (err ERR-NOT-FOUND)))
      (err ERR-NOT-FOUND)))
  )

;; Read-only function to get escrow details
(define-read-only (get-escrow (id uint))
  (begin
    ;; Validate input even for read-only functions
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    (ok (map-get? escrows id))))

;; Additional read-only functions for better UX
(define-read-only (get-escrow-state (id uint))
  (match (map-get? escrows id)
    val (ok (get state val))
    (err ERR-NOT-FOUND)))

(define-read-only (get-escrow-amount (id uint))
  (match (map-get? escrows id)
    val (ok (get amount val))
    (err ERR-NOT-FOUND)))

;; New read-only functions for timeout functionality
(define-read-only (is-expired (id uint))
  (match (map-get? escrows id)
    val (ok (is-escrow-expired val))
    (err ERR-NOT-FOUND)))

(define-read-only (get-expiration-block (id uint))
  (match (map-get? escrows id)
    val (ok (+ (get created-at val) (get timeout-blocks val)))
    (err ERR-NOT-FOUND)))

(define-read-only (get-time-remaining (id uint))
  (match (map-get? escrows id)
    val 
      (let ((expiration-block (+ (get created-at val) (get timeout-blocks val))))
        (if (> stacks-block-height expiration-block)
          (ok u0) ;; Already expired
          (ok (- expiration-block stacks-block-height))))
    (err ERR-NOT-FOUND)))

(define-read-only (get-escrow-created-at (id uint))
  (match (map-get? escrows id)
    val (ok (get created-at val))
    (err ERR-NOT-FOUND)))

(define-read-only (get-escrow-timeout-blocks (id uint))
  (match (map-get? escrows id)
    val (ok (get timeout-blocks val))
    (err ERR-NOT-FOUND)))
