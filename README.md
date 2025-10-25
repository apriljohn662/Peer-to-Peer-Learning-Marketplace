# 🎓 LearnChain - Peer-to-Peer Learning Marketplace

A decentralized platform built on Stacks blockchain where students connect with tutors for personalized learning sessions, with secure automatic payments through smart contracts.

## 🚀 Features

- **👨‍🏫 Tutor Registration**: Educators can register with their expertise and hourly rates
- **👩‍🎓 Student Enrollment**: Learners can create profiles and book sessions  
- **💰 Escrow Payments**: Automatic payment holding and release upon session completion
- **⭐ Rating System**: Mutual rating system for quality assurance
- **📊 Session Management**: Complete lifecycle management from booking to completion
- **🔒 Secure Transactions**: Built-in payment protection and dispute resolution

## 🏗️ Contract Functions

### Registration Functions
- `register-tutor(name, subject, hourly-rate)` - Register as a tutor
- `register-student(name)` - Register as a student

### Session Management
- `create-session(tutor, subject, duration, starts-at)` - Book a new session with escrow
- `accept-session(session-id)` - Tutor accepts pending session
- `start-session(session-id)` - Begin the learning session
- `complete-session(session-id)` - Mark session complete and release payment
- `cancel-session(session-id)` - Cancel session with refund

### Rating & Reviews
- `rate-session(session-id, rating, review)` - Rate completed sessions (1-5 stars)

### Profile Management  
- `update-tutor-profile(name, subject, hourly-rate)` - Update tutor information
- `deactivate-account()` - Deactivate user account

## 🔍 Read-Only Functions

- `get-tutor(principal)` - Get tutor profile data
- `get-student(principal)` - Get student profile data  
- `get-session(session-id)` - Get session details
- `get-session-payment(session-id)` - Get payment information
- `get-session-review(session-id)` - Get session reviews
- `calculate-session-cost(duration, hourly-rate)` - Calculate total cost including fees
- `get-platform-fee()` - Current platform fee percentage

## 📖 Usage Example

```clarity
;; 1. Register as a tutor
(contract-call? .LearnChain register-tutor "Alice Smith" "Mathematics" u100)

;; 2. Register as a student  
(contract-call? .LearnChain register-student "Bob Johnson")

;; 3. Student creates a session (2-hour math tutoring)
(contract-call? .LearnChain create-session 'SP2...(tutor-address) "Mathematics" u2 u1000)

;; 4. Tutor accepts the session
(contract-call? .LearnChain accept-session u1)

;; 5. Start the session
(contract-call? .LearnChain start-session u1)

;; 6. Complete session (releases payment)
(contract-call? .LearnChain complete-session u1)

;; 7. Rate the session
(contract-call? .LearnChain rate-session u1 u5 "Excellent tutor!")
```

## ⚙️ Session States

- **pending** → **accepted** → **active** → **completed**
- **pending** → **cancelled** (refund issued)
- **active** → **expired** (auto-refund after 144 blocks)

## 💳 Payment Flow

1. Student pays total cost + platform fee (5% default) when creating session
2. Funds held in escrow until session completion
3. Upon completion: tutor receives payment, platform receives fee
4. Cancellations trigger automatic refunds

## 🛠️ Development

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Commands
```bash
# Check contract syntax
clarinet check

# Run tests
clarinet test

# Deploy locally  
clarinet integrate
```

## 🔐 Security Features

- ✅ Payment escrow protection
- ✅ Session expiry handling  
- ✅ Access control for all functions
- ✅ Automatic refunds for cancellations
- ✅ Protected admin functions

## 📊 Platform Economics

- **Default Platform Fee**: 5% (adjustable by contract owner)
- **Payment Model**: Pay-per-session with upfront escrow
- **Fee Distribution**: Tutor receives full rate, platform receives percentage fee
- **Refund Policy**: Full refunds for cancelled or expired sessions

---

*Built with ❤️ on Stacks blockchain*
