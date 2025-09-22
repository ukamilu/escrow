(define-map escrows uint { buyer: principal, seller: principal, arbitrator: principal, amount: uint, state: uint })
;; states: 0 = funded, 1 = released, 2 = disputed

;; Error codes
(define-constant ERR-NOT-FOUND u1)
(define-constant ERR-ALREADY-EXISTS u2)
(define-constant ERR-INVALID-STATE u3)
(define-constant ERR-UNAUTHORIZED u4)
(define-constant ERR-INVALID-AMOUNT u5)
(define-constant ERR-INVALID-PRINCIPAL u6)
(define-constant ERR-INVALID-ID u7)

;; Constants for validation
(define-constant MIN-AMOUNT u1000000) ;; Minimum 1 STX in microSTX
(define-constant MAX-AMOUNT u1000000000000) ;; Maximum amount
(define-constant MAX-ESCROW-ID u999999999) ;; Maximum escrow ID

;; Input validation functions
(define-private (is-valid-principal (p principal))
  (not (is-eq p tx-sender))) ;; Prevent self-transactions

(define-private (is-valid-amount (amount uint))
  (and (>= amount MIN-AMOUNT) (<= amount MAX-AMOUNT)))

(define-private (is-valid-id (id uint))
  (and (> id u0) (<= id MAX-ESCROW-ID)))

(define-public (create-escrow (id uint) (seller principal) (arb principal) (amount uint))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    (asserts! (is-valid-amount amount) (err ERR-INVALID-AMOUNT))
    (asserts! (is-valid-principal seller) (err ERR-INVALID-PRINCIPAL))
    (asserts! (is-valid-principal arb) (err ERR-INVALID-PRINCIPAL))
    (asserts! (not (is-eq seller arb)) (err ERR-INVALID-PRINCIPAL))
    (asserts! (not (is-eq tx-sender seller)) (err ERR-INVALID-PRINCIPAL))
    (asserts! (not (is-eq tx-sender arb)) (err ERR-INVALID-PRINCIPAL))
    
    ;; Check if escrow ID already exists
    (asserts! (is-none (map-get? escrows id)) (err ERR-ALREADY-EXISTS))
    
    ;; Transfer funds from buyer to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Create escrow record with validated inputs
    (map-set escrows id { 
      buyer: tx-sender, 
      seller: seller, 
      arbitrator: arb, 
      amount: amount, 
      state: u0 
    })
    (ok true)))

(define-public (release (id uint))
  (begin
    ;; Validate input
    (asserts! (is-valid-id id) (err ERR-INVALID-ID))
    
    (let ((e (map-get? escrows id)))
      (match e
        val
          (begin
            ;; Check if escrow is in funded state
            (asserts! (is-eq (get state val) u0) (err ERR-INVALID-STATE))
            ;; Only buyer or arbitrator can release funds
            (asserts! (or (is-eq tx-sender (get buyer val)) 
                         (is-eq tx-sender (get arbitrator val))) 
                     (err ERR-UNAUTHORIZED))
            ;; Transfer funds from contract to seller
            (try! (as-contract (stx-transfer? (get amount val) tx-sender (get seller val))))
            ;; Update escrow state to released
            (map-set escrows id { 
              buyer: (get buyer val), 
              seller: (get seller val), 
              arbitrator: (get arbitrator val), 
              amount: (get amount val), 
              state: u1 
            })
            (ok true))
        (err ERR-NOT-FOUND)))))

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
            (map-set escrows id { 
              buyer: (get buyer val), 
              seller: (get seller val), 
              arbitrator: (get arbitrator val), 
              amount: (get amount val), 
              state: u2 
            })
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
            (map-set escrows id { 
              buyer: (get buyer val), 
              seller: (get seller val), 
              arbitrator: (get arbitrator val), 
              amount: (get amount val), 
              state: u1 
            })
            (ok true))
        (err ERR-NOT-FOUND)))))

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