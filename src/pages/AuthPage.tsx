import { useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Phone, Mail, ArrowRight, ShieldCheck } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/components/Toast'
import { errorMessage } from '@/lib/errors'

type Mode = 'phone' | 'email'

export function AuthPage() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const nextUrl = params.get('next') || '/'
  const { toast } = useToast()

  const [mode, setMode] = useState<Mode>('phone')
  const [phone, setPhone] = useState('')
  const [email, setEmail] = useState('')
  const [otpSent, setOtpSent] = useState(false)
  const [otp, setOtp] = useState('')
  const [busy, setBusy] = useState(false)

  const formattedPhone = `+91${phone.replace(/\D/g, '').slice(-10)}`

  const handleSendOtp = async (e: React.FormEvent) => {
    e.preventDefault()
    setBusy(true)
    try {
      if (mode === 'phone') {
        const digits = phone.replace(/\D/g, '')
        if (digits.length !== 10) {
          toast('Enter a valid 10-digit Indian mobile number', 'error')
          setBusy(false)
          return
        }
        const { error } = await supabase.auth.signInWithOtp({ phone: formattedPhone })
        if (error) {
          if (/Phone.*disabled|Unsupported phone provider/i.test(error.message)) {
            toast(
              'Phone SMS provider is not enabled yet in Supabase Auth. Switching to Email OTP.',
              'info',
            )
            setMode('email')
            setBusy(false)
            return
          }
          throw error
        }
        setOtpSent(true)
        toast(`OTP sent to ${formattedPhone}`, 'success')
      } else {
        if (!email.includes('@')) {
          toast('Enter a valid email address', 'error')
          setBusy(false)
          return
        }
        const { error } = await supabase.auth.signInWithOtp({
          email: email.trim(),
          options: { shouldCreateUser: true },
        })
        if (error) throw error
        setOtpSent(true)
        toast(`Verification code sent to ${email}`, 'success')
      }
    } catch (err) {
      toast(errorMessage(err), 'error')
    } finally {
      setBusy(false)
    }
  }

  const handleVerifyOtp = async (e: React.FormEvent) => {
    e.preventDefault()
    if (otp.trim().length < 6) {
      toast('Enter the 6-digit OTP code', 'error')
      return
    }
    setBusy(true)
    try {
      const res =
        mode === 'phone'
          ? await supabase.auth.verifyOtp({ phone: formattedPhone, token: otp.trim(), type: 'sms' })
          : await supabase.auth.verifyOtp({ email: email.trim(), token: otp.trim(), type: 'email' })
      if (res.error) throw res.error

      const uid = res.data.user?.id
      if (uid && !nextUrl.startsWith('/owner')) {
        const { data: prof } = await supabase
          .from('profiles')
          .select('onboarded')
          .eq('id', uid)
          .maybeSingle()
        if (!prof || !(prof as { onboarded?: boolean }).onboarded) {
          navigate(`/onboarding?next=${encodeURIComponent(nextUrl)}`, { replace: true })
          return
        }
      }
      toast('Signed in!', 'success')
      navigate(nextUrl, { replace: true })
    } catch (err) {
      toast(errorMessage(err), 'error')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="p-4 pt-8 max-w-md mx-auto space-y-6 safe-top">
      <div className="space-y-2 text-center">
        <div className="w-14 h-14 rounded-2xl bg-neon/15 border border-neon/40 text-neon font-display text-2xl font-bold flex items-center justify-center mx-auto">
          T
        </div>
        <h1 className="text-2xl font-bold">Welcome to Turffet</h1>
        <p className="text-xs text-muted">
          Book turfs across Delhi NCR, get instant QR passes and join open games near you.
        </p>
      </div>

      {/* Mode toggle */}
      <div className="grid grid-cols-2 rounded-xl bg-surface p-1 border border-line">
        <button
          type="button"
          onClick={() => {
            setMode('phone')
            setOtpSent(false)
          }}
          className={`h-9 rounded-lg text-xs font-semibold flex items-center justify-center gap-1.5 transition ${
            mode === 'phone' ? 'bg-neon text-ink' : 'text-muted hover:text-text'
          }`}
        >
          <Phone className="w-3.5 h-3.5" />
          <span>Phone + OTP</span>
        </button>
        <button
          type="button"
          onClick={() => {
            setMode('email')
            setOtpSent(false)
          }}
          className={`h-9 rounded-lg text-xs font-semibold flex items-center justify-center gap-1.5 transition ${
            mode === 'email' ? 'bg-neon text-ink' : 'text-muted hover:text-text'
          }`}
        >
          <Mail className="w-3.5 h-3.5" />
          <span>Email OTP</span>
        </button>
      </div>

      <div className="card p-5 space-y-4">
        {!otpSent ? (
          <form onSubmit={handleSendOtp} className="space-y-4">
            {mode === 'phone' ? (
              <div className="space-y-1.5">
                <label className="label" htmlFor="phone-input">
                  Mobile Number (India)
                </label>
                <div className="flex items-center gap-2">
                  <div className="h-12 px-3.5 rounded-xl bg-surface-2 border border-line flex items-center text-sm font-semibold text-muted shrink-0">
                    🇮🇳 +91
                  </div>
                  <input
                    id="phone-input"
                    type="tel"
                    inputMode="numeric"
                    maxLength={10}
                    value={phone}
                    onChange={(e) => setPhone(e.target.value.replace(/\D/g, ''))}
                    placeholder="98765 43210"
                    className="input tracking-wider"
                    required
                  />
                </div>
                <div className="flex items-center justify-between pt-1">
                  <span className="text-[11px] text-muted">Testing without SMS gateway?</span>
                  <button
                    type="button"
                    onClick={() => {
                      setPhone('9876543210')
                      setOtp('123456')
                    }}
                    className="text-[11px] text-neon font-semibold hover:underline"
                  >
                    Fill test phone (+91 98765 43210 · OTP 123456)
                  </button>
                </div>
              </div>
            ) : (
              <div className="space-y-1.5">
                <label className="label" htmlFor="email-input">
                  Email Address
                </label>
                <input
                  id="email-input"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  className="input"
                  required
                />
              </div>
            )}

            <button type="submit" disabled={busy} className="btn-primary w-full h-12 shadow-glow">
              <span>{busy ? 'Sending OTP…' : 'Send 6-digit OTP'}</span>
              <ArrowRight className="w-4 h-4" />
            </button>
          </form>
        ) : (
          <form onSubmit={handleVerifyOtp} className="space-y-4">
            <div className="space-y-1.5">
              <div className="flex items-center justify-between">
                <label className="label" htmlFor="otp-input">
                  Enter 6-digit OTP
                </label>
                <button
                  type="button"
                  onClick={() => {
                    setOtpSent(false)
                    setOtp('')
                  }}
                  className="text-xs text-neon font-semibold"
                >
                  Change {mode === 'phone' ? 'number' : 'email'}
                </button>
              </div>
              <input
                id="otp-input"
                type="text"
                inputMode="numeric"
                maxLength={6}
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
                placeholder="• • • • • •"
                className="input text-center text-xl font-mono tracking-[0.5em]"
                autoFocus
                required
              />
            </div>

            <button type="submit" disabled={busy} className="btn-primary w-full h-12 shadow-glow">
              {busy ? 'Verifying…' : 'Verify & Continue'}
            </button>
          </form>
        )}

        <div className="flex items-start gap-2 pt-2 border-t border-line text-[11px] text-muted">
          <ShieldCheck className="w-4 h-4 text-neon shrink-0 mt-0.5" />
          <span>
            Your number is only used for booking passes and game updates. No spam, ever.
          </span>
        </div>
      </div>
    </div>
  )
}
