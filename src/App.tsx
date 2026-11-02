import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthProvider } from '@/lib/auth'
import { LocationProvider } from '@/lib/location'
import { ToastProvider } from '@/components/Toast'
import { RoleGateProvider } from '@/components/RoleGateway'
import { Layout } from '@/components/Layout'
import { OwnerLayout } from '@/components/OwnerLayout'
import { ExplorePage } from '@/pages/ExplorePage'
import { TurfDetailPage } from '@/pages/TurfDetailPage'
import { BookingsPage } from '@/pages/BookingsPage'
import { BookingPassPage } from '@/pages/BookingPassPage'
import { GamesPage } from '@/pages/GamesPage'
import { GameDetailPage } from '@/pages/GameDetailPage'
import { FavouritesPage } from '@/pages/FavouritesPage'
import { NotificationsPage } from '@/pages/NotificationsPage'
import { AuthPage } from '@/pages/AuthPage'
import { OnboardingPage } from '@/pages/OnboardingPage'
import { ProfilePage } from '@/pages/ProfilePage'
import { OwnerDashboardPage } from '@/pages/owner/OwnerDashboardPage'
import { OwnerTurfEditorPage } from '@/pages/owner/OwnerTurfEditorPage'
import { OwnerScanPage } from '@/pages/owner/OwnerScanPage'
import { OwnerBookingsPage } from '@/pages/owner/OwnerBookingsPage'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 30,
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <LocationProvider>
          <ToastProvider>
            <BrowserRouter>
              <RoleGateProvider>
                <Routes>
                  {/* Player / Client App */}
                  <Route element={<Layout />}>
                    <Route index element={<ExplorePage />} />
                    <Route path="turf/:slug" element={<TurfDetailPage />} />
                    <Route path="bookings" element={<BookingsPage />} />
                    <Route path="bookings/:id" element={<BookingPassPage />} />
                    <Route path="games" element={<GamesPage />} />
                    <Route path="games/:id" element={<GameDetailPage />} />
                    <Route path="saved" element={<FavouritesPage />} />
                    <Route path="notifications" element={<NotificationsPage />} />
                    <Route path="auth" element={<AuthPage />} />
                    <Route path="onboarding" element={<OnboardingPage />} />
                    <Route path="profile" element={<ProfilePage />} />
                  </Route>

                  {/* Turf Owner Portal */}
                  <Route path="owner" element={<OwnerLayout />}>
                    <Route index element={<OwnerDashboardPage />} />
                    <Route path="turfs/new" element={<OwnerTurfEditorPage />} />
                    <Route path="turfs/:id/edit" element={<OwnerTurfEditorPage />} />
                    <Route path="scan" element={<OwnerScanPage />} />
                    <Route path="bookings" element={<OwnerBookingsPage />} />
                  </Route>

                  <Route path="*" element={<Navigate to="/" replace />} />
                </Routes>
              </RoleGateProvider>
            </BrowserRouter>
          </ToastProvider>
        </LocationProvider>
      </AuthProvider>
    </QueryClientProvider>
  )
}
