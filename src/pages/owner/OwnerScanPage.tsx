import { useEffect, useRef, useState } from 'react'
import jsQR from 'jsqr'
import {
  Camera,
  CameraOff,
  CheckCircle2,
  QrCode,
  Search,
  ShieldCheck,
  ShieldAlert,
  Users,
  Clock,
  Phone,
  MapPin,
  RotateCcw,
} from 'lucide-react'
import { useOwnerCheckIn, useOwnerLookupBooking } from '@/lib/ownerApi'
import { useSports } from '@/lib/api'
import { formatDay, formatINR, formatRange } from '@/lib/format'
import { useToast } from '@/components/Toast'
import { errorMessage } from '@/lib/errors'
import type { OwnerLookupBookingResult } from '@/lib/types'

export function OwnerScanPage() {
  const { data: sports = [] } = useSports()
  const lookupBooking = useOwnerLookupBooking()
  const checkIn = useOwnerCheckIn()
  const { toast } = useToast()

  const [codeQuery, setCodeQuery] = useState('')
  const [cameraActive, setCameraActive] = useState(false)
  const [cameraError, setCameraError] = useState<string | null>(null)
  const [result, setResult] = useState<OwnerLookupBookingResult | null>(null)
  const [lastScannedRaw, setLastScannedRaw] = useState<string | null>(null)

  const videoRef = useRef<HTMLVideoElement | null>(null)
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const rafRef = useRef<number | null>(null)
  const streamRef = useRef<MediaStream | null>(null)

  const stopCamera = () => {
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop())
      streamRef.current = null
    }
    setCameraActive(false)
  }

  useEffect(() => {
    return () => {
      stopCamera()
    }
  }, [])

  const handleLookup = async (rawQuery: string) => {
    const cleaned = rawQuery.trim()
    if (!cleaned) return
    try {
      const found = await lookupBooking.mutateAsync(cleaned)
      setResult(found)
      setLastScannedRaw(cleaned.startsWith('TFT1.') ? cleaned : null)
      stopCamera()
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  const startCamera = async () => {
    setCameraError(null)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' } },
        audio: false,
      })
      streamRef.current = stream
      setCameraActive(true)
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        await videoRef.current.play()
      }

      const tick = () => {
        const video = videoRef.current
        const canvas = canvasRef.current
        if (video && canvas && video.readyState === video.HAVE_ENOUGH_DATA) {
          canvas.width = video.videoWidth
          canvas.height = video.videoHeight
          const ctx = canvas.getContext('2d')
          if (ctx) {
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
            const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height)
            const qr = jsQR(imageData.data, imageData.width, imageData.height, {
              inversionAttempts: 'dontInvert',
            })
            if (qr?.data) {
              handleLookup(qr.data)
              return
            }
          }
        }
        rafRef.current = requestAnimationFrame(tick)
      }
      rafRef.current = requestAnimationFrame(tick)
    } catch {
      setCameraError(
        'Camera permission denied or unavailable. You can enter the 6-character booking code below.',
      )
      setCameraActive(false)
    }
  }

  const handleConfirmCheckIn = async () => {
    if (!result) return
    try {
      await checkIn.mutateAsync({
        bookingId: result.id,
        qrToken: lastScannedRaw || result.qr_token,
      })
      toast(`Checked in ${result.player.name} (${result.players_count} players)!`, 'success')
      setResult({
        ...result,
        status: 'checked_in',
        checked_in_at: new Date().toISOString(),
      })
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  const sportObj = sports.find((s) => s.id === result?.sport_id)

  return (
    <div className="p-4 space-y-5">
      <div>
        <h1 className="text-xl font-extrabold text-text">QR Scanner & Player Check-In</h1>
        <p className="text-xs text-muted">
          Scan the player’s Turffet QR booking pass or enter their 6-character booking code when they arrive at the turf
        </p>
      </div>

      {/* Camera Scanner Box */}
      <div className="card p-4 space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-sm font-bold text-text">
            <QrCode className="w-4 h-4 text-neon" />
            <span>Camera QR Pass Scanner</span>
          </div>
          {cameraActive ? (
            <button type="button" onClick={stopCamera} className="btn-secondary h-8 px-3 text-xs">
              <CameraOff className="w-3.5 h-3.5 text-danger" />
              <span>Stop Camera</span>
            </button>
          ) : (
            <button
              type="button"
              onClick={startCamera}
              className="btn-primary h-9 px-3.5 text-xs shadow-glow"
            >
              <Camera className="w-3.5 h-3.5" />
              <span>Open Camera Scanner</span>
            </button>
          )}
        </div>

        {cameraActive && (
          <div className="relative aspect-square max-w-xs mx-auto rounded-2xl overflow-hidden border-2 border-neon bg-black">
            <video ref={videoRef} playsInline muted className="w-full h-full object-cover" />
            <canvas ref={canvasRef} className="hidden" />
            <div className="absolute inset-8 border-2 border-neon/70 rounded-2xl pointer-events-none" />
            <div className="absolute bottom-3 inset-x-0 text-center text-[11px] font-semibold text-neon bg-ink/80 py-1">
              Point camera at player’s Turffet QR Pass…
            </div>
          </div>
        )}

        {cameraError && (
          <div className="rounded-xl bg-warn/10 border border-warn/30 p-3 text-xs text-warn">
            {cameraError}
          </div>
        )}

        {/* Manual Code Lookup */}
        <form
          onSubmit={(e) => {
            e.preventDefault()
            handleLookup(codeQuery)
          }}
          className="pt-2 border-t border-line space-y-2"
        >
          <label className="label">Or enter 6-character Booking Code / QR Token</label>
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="w-4 h-4 text-muted absolute left-3.5 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={codeQuery}
                onChange={(e) => setCodeQuery(e.target.value.toUpperCase())}
                placeholder="e.g. A8K4P9 or TFT1...."
                className="input h-11 pl-10 text-sm font-mono uppercase tracking-wider"
              />
            </div>
            <button
              type="submit"
              disabled={lookupBooking.isPending || !codeQuery.trim()}
              className="btn-primary h-11 px-5 text-xs"
            >
              {lookupBooking.isPending ? 'Verifying…' : 'Verify Pass'}
            </button>
          </div>
        </form>
      </div>

      {/* Verified Booking Result Card */}
      {result && (
        <div className="card p-5 space-y-4 border-neon/50 animate-fade-up">
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-2.5">
              {result.signature_valid ? (
                <div className="w-10 h-10 rounded-xl bg-neon/15 border border-neon/40 text-neon flex items-center justify-center shrink-0">
                  <ShieldCheck className="w-5 h-5" />
                </div>
              ) : (
                <div className="w-10 h-10 rounded-xl bg-danger/15 border border-danger/40 text-danger flex items-center justify-center shrink-0">
                  <ShieldAlert className="w-5 h-5" />
                </div>
              )}
              <div>
                <div className="flex items-center gap-2">
                  <span className="font-mono text-base font-extrabold text-neon">
                    #{result.code}
                  </span>
                  <span
                    className={`rounded-full px-2.5 py-0.5 text-[10px] font-extrabold uppercase ${
                      result.status === 'checked_in'
                        ? 'bg-neon text-ink'
                        : result.status === 'confirmed'
                          ? 'bg-neon/15 text-neon border border-neon/30'
                          : 'bg-danger/15 text-danger'
                    }`}
                  >
                    {result.status.replace('_', ' ')}
                  </span>
                </div>
                <div className="text-xs text-muted">
                  {result.signature_valid
                    ? 'Authentic HMAC-verified Turffet booking pass'
                    : 'Warning: QR signature mismatch'}
                </div>
              </div>
            </div>

            <button
              type="button"
              onClick={() => {
                setResult(null)
                setCodeQuery('')
              }}
              className="btn-secondary h-8 px-2.5 text-xs"
            >
              <RotateCcw className="w-3.5 h-3.5" />
              <span>Clear</span>
            </button>
          </div>

          <div className="rounded-2xl bg-surface-2 border border-line p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <div className="text-sm font-bold text-text">{result.turf.name}</div>
                <div className="text-xs text-muted flex items-center gap-1">
                  <MapPin className="w-3 h-3 text-neon" />
                  <span>
                    {result.court.name} {result.court.size_label ? `· ${result.court.size_label}` : ''}
                  </span>
                </div>
              </div>
              <div className="text-right">
                <div className="text-lg font-extrabold text-neon">
                  {formatINR(result.total_price)}
                </div>
                <div className="text-[10px] text-muted">Collect at venue</div>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-2.5 pt-2 border-t border-line text-xs">
              <div className="space-y-0.5">
                <span className="text-muted">Date & Slot Time</span>
                <div className="font-bold text-text flex items-center gap-1">
                  <Clock className="w-3.5 h-3.5 text-neon shrink-0" />
                  <span>
                    {formatDay(result.starts_at)} · {formatRange(result.starts_at, result.ends_at)}
                  </span>
                </div>
              </div>

              <div className="space-y-0.5">
                <span className="text-muted">Sport & Group Size</span>
                <div className="font-bold text-text flex items-center gap-1.5">
                  <span>
                    {sportObj?.emoji ?? '🏟️'} {sportObj?.name ?? result.sport_id}
                  </span>
                  <span className="text-neon inline-flex items-center gap-1">
                    · <Users className="w-3.5 h-3.5" /> {result.players_count} players
                  </span>
                </div>
              </div>

              <div className="space-y-0.5">
                <span className="text-muted">Booked By</span>
                <div className="font-bold text-text">{result.player.name}</div>
              </div>

              <div className="space-y-0.5">
                <span className="text-muted">Player Phone</span>
                <div>
                  {result.player.phone ? (
                    <a
                      href={`tel:${result.player.phone}`}
                      className="font-bold text-neon inline-flex items-center gap-1 hover:underline"
                    >
                      <Phone className="w-3 h-3" />
                      {result.player.phone}
                    </a>
                  ) : (
                    <span className="text-muted">—</span>
                  )}
                </div>
              </div>
            </div>

            {result.note && (
              <div className="pt-2 border-t border-line text-xs text-muted">
                <strong className="text-text">Player note:</strong> {result.note}
              </div>
            )}
          </div>

          {result.status === 'checked_in' ? (
            <div className="rounded-xl bg-neon/15 border border-neon/40 p-3.5 flex items-center justify-center gap-2 text-sm font-bold text-neon">
              <CheckCircle2 className="w-5 h-5" />
              <span>Player Checked In Successfully</span>
            </div>
          ) : result.status === 'confirmed' ? (
            <button
              type="button"
              onClick={handleConfirmCheckIn}
              disabled={checkIn.isPending || !result.signature_valid}
              className="btn-primary w-full h-12 text-sm shadow-glow"
            >
              <CheckCircle2 className="w-4 h-4" />
              <span>
                {checkIn.isPending
                  ? 'Confirming Check-In…'
                  : `Confirm Check-In · ${result.players_count} Players`}
              </span>
            </button>
          ) : (
            <div className="rounded-xl bg-danger/15 border border-danger/30 p-3 text-center text-xs font-bold text-danger">
              This booking is {result.status.replace('_', ' ')} and cannot be checked in.
            </div>
          )}
        </div>
      )}
    </div>
  )
}
