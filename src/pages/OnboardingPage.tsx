import { useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/lib/auth'
import { useSports } from '@/lib/api'
import { SKILL_LABEL } from '@/lib/format'
import { useToast } from '@/components/Toast'
import { errorMessage } from '@/lib/errors'
import type { SkillLevel } from '@/lib/types'

export function OnboardingPage() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const nextUrl = params.get('next') || '/'
  const { user, profile, refreshProfile } = useAuth()
  const { data: sports = [] } = useSports()
  const { toast } = useToast()

  const [fullName, setFullName] = useState(profile?.full_name ?? '')
  const [preferredSports, setPreferredSports] = useState<string[]>(
    profile?.preferred_sports?.length ? profile.preferred_sports : ['football', 'cricket'],
  )
  const [skill, setSkill] = useState<SkillLevel>(profile?.skill_level ?? 'intermediate')
  const [busy, setBusy] = useState(false)

  const toggleSport = (id: string) => {
    setPreferredSports((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id],
    )
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!fullName.trim()) {
      toast('Please enter your name', 'error')
      return
    }
    if (!user) {
      navigate('/auth')
      return
    }
    setBusy(true)
    try {
      const { error } = await supabase
        .from('profiles')
        .update({
          full_name: fullName.trim(),
          preferred_sports: preferredSports,
          skill_level: skill,
          onboarded: true,
        })
        .eq('id', user.id)
      if (error) throw error
      await refreshProfile()
      toast('Profile ready! Let’s find a turf.', 'success')
      navigate(nextUrl, { replace: true })
    } catch (err) {
      toast(errorMessage(err), 'error')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="p-4 pt-6 max-w-md mx-auto space-y-5 safe-top">
      <div>
        <h1 className="text-2xl font-bold">Set up your player profile</h1>
        <p className="text-xs text-muted mt-1">
          Helps hosts know who’s joining their game and personalises your turf feed.
        </p>
      </div>

      <form onSubmit={handleSave} className="card p-5 space-y-5">
        <div className="space-y-1.5">
          <label className="label" htmlFor="full-name">
            Your Name
          </label>
          <input
            id="full-name"
            type="text"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            placeholder="e.g. Ritik Sharma"
            className="input"
            required
          />
        </div>

        <div className="space-y-2">
          <div className="label">Sports you play</div>
          <div className="flex flex-wrap gap-2">
            {sports.map((s) => {
              const active = preferredSports.includes(s.id)
              return (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => toggleSport(s.id)}
                  className={active ? 'chip-active' : 'chip'}
                >
                  <span>{s.emoji}</span>
                  <span>{s.name}</span>
                </button>
              )
            })}
          </div>
        </div>

        <div className="space-y-2">
          <div className="label">Your skill level</div>
          <div className="grid grid-cols-3 gap-2">
            {(['beginner', 'intermediate', 'advanced'] as SkillLevel[]).map((lv) => (
              <button
                key={lv}
                type="button"
                onClick={() => setSkill(lv)}
                className={`rounded-xl border py-2.5 text-xs font-semibold transition ${
                  skill === lv
                    ? 'border-neon bg-neon/10 text-neon'
                    : 'border-line bg-surface-2 text-text'
                }`}
              >
                {SKILL_LABEL[lv]}
              </button>
            ))}
          </div>
        </div>

        <button type="submit" disabled={busy} className="btn-primary w-full h-12 shadow-glow">
          {busy ? 'Saving…' : 'Start Exploring Turfs'}
        </button>
      </form>
    </div>
  )
}
