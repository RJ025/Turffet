export interface Area {
  id: string
  label: string
  region: 'Delhi' | 'Gurugram' | 'Noida' | 'Ghaziabad' | 'Faridabad'
  lat: number
  lng: number
}

/** Quick-pick areas across Delhi NCR (used when GPS is off/denied). */
export const AREAS: Area[] = [
  { id: 'cp', label: 'Connaught Place', region: 'Delhi', lat: 28.6315, lng: 77.2167 },
  { id: 'hauz-khas', label: 'Hauz Khas', region: 'Delhi', lat: 28.5494, lng: 77.2001 },
  { id: 'saket', label: 'Saket', region: 'Delhi', lat: 28.5245, lng: 77.2066 },
  { id: 'lajpat', label: 'Lajpat Nagar', region: 'Delhi', lat: 28.5677, lng: 77.2433 },
  { id: 'vasant-kunj', label: 'Vasant Kunj', region: 'Delhi', lat: 28.52, lng: 77.158 },
  { id: 'dwarka', label: 'Dwarka', region: 'Delhi', lat: 28.5921, lng: 77.046 },
  { id: 'rajouri', label: 'Rajouri Garden', region: 'Delhi', lat: 28.6415, lng: 77.1209 },
  { id: 'pitampura', label: 'Pitampura', region: 'Delhi', lat: 28.699, lng: 77.139 },
  { id: 'rohini', label: 'Rohini', region: 'Delhi', lat: 28.7158, lng: 77.115 },
  { id: 'mayur-vihar', label: 'Mayur Vihar', region: 'Delhi', lat: 28.604, lng: 77.294 },
  { id: 'cyber-city', label: 'Cyber City', region: 'Gurugram', lat: 28.495, lng: 77.089 },
  { id: 'golf-course', label: 'Golf Course Road', region: 'Gurugram', lat: 28.439, lng: 77.103 },
  { id: 'sohna-road', label: 'Sohna Road', region: 'Gurugram', lat: 28.413, lng: 77.043 },
  { id: 'noida-18', label: 'Sector 18', region: 'Noida', lat: 28.57, lng: 77.326 },
  { id: 'noida-62', label: 'Sector 62', region: 'Noida', lat: 28.627, lng: 77.365 },
  { id: 'gnw', label: 'Greater Noida West', region: 'Noida', lat: 28.608, lng: 77.43 },
  { id: 'indirapuram', label: 'Indirapuram', region: 'Ghaziabad', lat: 28.646, lng: 77.369 },
  { id: 'faridabad', label: 'Faridabad', region: 'Faridabad', lat: 28.428, lng: 77.306 },
]

export const DEFAULT_AREA = AREAS[0]!
