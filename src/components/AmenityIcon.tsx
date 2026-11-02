import {
  Car,
  Lightbulb,
  Bath,
  Shirt,
  GlassWater,
  ShowerHead,
  Coffee,
  Package,
  Armchair,
  Cross,
  Cctv,
  Snowflake,
  Wifi,
  CheckCircle2,
} from 'lucide-react'

export function AmenityIcon({ icon, className = 'w-4 h-4' }: { icon: string; className?: string }) {
  switch (icon) {
    case 'car':
      return <Car className={className} />
    case 'lightbulb':
      return <Lightbulb className={className} />
    case 'bath':
      return <Bath className={className} />
    case 'shirt':
      return <Shirt className={className} />
    case 'glass-water':
      return <GlassWater className={className} />
    case 'shower-head':
      return <ShowerHead className={className} />
    case 'coffee':
      return <Coffee className={className} />
    case 'package':
      return <Package className={className} />
    case 'armchair':
      return <Armchair className={className} />
    case 'cross':
      return <Cross className={className} />
    case 'cctv':
      return <Cctv className={className} />
    case 'snowflake':
      return <Snowflake className={className} />
    case 'wifi':
      return <Wifi className={className} />
    default:
      return <CheckCircle2 className={className} />
  }
}
