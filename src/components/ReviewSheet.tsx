import { useState } from 'react'
import { Star } from 'lucide-react'
import { BottomSheet } from './BottomSheet'
import { useSubmitReview } from '@/lib/api'
import { useToast } from './Toast'
import { errorMessage } from '@/lib/errors'

interface Props {
  open: boolean
  onClose: () => void
  bookingId: string
  turfName: string
  initialRating?: number
  initialComment?: string | null
}

export function ReviewSheet({
  open,
  onClose,
  bookingId,
  turfName,
  initialRating = 5,
  initialComment = '',
}: Props) {
  const [rating, setRating] = useState(initialRating)
  const [comment, setComment] = useState(initialComment ?? '')
  const submitReview = useSubmitReview()
  const { toast } = useToast()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    try {
      await submitReview.mutateAsync({ bookingId, rating, comment })
      toast('Thanks for reviewing!', 'success')
      onClose()
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  return (
    <BottomSheet open={open} onClose={onClose} title={`Rate ${turfName}`}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="flex flex-col items-center gap-2 py-2">
          <div className="flex items-center gap-2">
            {[1, 2, 3, 4, 5].map((n) => (
              <button
                key={n}
                type="button"
                onClick={() => setRating(n)}
                className="p-1.5 transition transform active:scale-90"
              >
                <Star
                  className={`w-8 h-8 ${
                    n <= rating ? 'fill-neon text-neon' : 'text-surface-3 stroke-muted'
                  }`}
                />
              </button>
            ))}
          </div>
          <div className="text-xs font-medium text-muted">
            {rating === 5
              ? 'Awesome pitch & lighting!'
              : rating === 4
                ? 'Good game, would book again'
                : rating === 3
                  ? 'Decent, could be better'
                  : 'Needs improvement'}
          </div>
        </div>

        <div className="space-y-1.5">
          <label className="label" htmlFor="review-comment">
            How was the turf, grass & lighting?
          </label>
          <textarea
            id="review-comment"
            rows={3}
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            placeholder="Share tips for other players (shoes, surface, parking)…"
            maxLength={400}
            className="input h-auto py-3 text-sm"
          />
        </div>

        <button type="submit" disabled={submitReview.isPending} className="btn-primary w-full">
          {submitReview.isPending ? 'Saving…' : 'Submit review'}
        </button>
      </form>
    </BottomSheet>
  )
}
