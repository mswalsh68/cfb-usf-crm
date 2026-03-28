// ─── Roles & Permissions ────────────────────────────────────────────────────

export type AppName = 'roster' | 'alumni' | 'global-admin';

export type GlobalRole =
  | 'platform_owner'  // SaaS operator — access to all teams and platform admin
  | 'global_admin'    // Full access to their team, all apps
  | 'app_admin'       // Admin within their assigned app(s)
  | 'coach_staff'     // Read/write in assigned app(s)
  | 'player'          // Access to roster app only (self-record)
  | 'readonly';       // View-only in assigned app(s)

export interface AppPermission {
  app: AppName;
  role: GlobalRole;
  grantedAt: string;
  grantedBy: string;
}

// ─── Multi-tenant team summary (embedded in JWT) ──────────────────────────────

export interface TeamSummary {
  teamId:       string;
  abbr:         string;
  name:         string;
  role:         string;
  logoUrl?:     string;
  colorPrimary: string;
  colorAccent:  string;
}

// ─── User ────────────────────────────────────────────────────────────────────

export interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  globalRole: GlobalRole;
  appPermissions: AppPermission[];
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface AuthTokenPayload {
  sub:            string;            // user id
  email:          string;
  globalRole:     GlobalRole;
  currentTeamId:  string;           // active team for this session
  teams:          TeamSummary[];    // all teams this user can access
  appPermissions: AppPermission[];
  // Current team DB routing (derived from currentTeamId at login/switch)
  appDb:    string;
  dbServer: string;
  iat: number;
  exp: number;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  accessToken: string;
  refreshToken: string;
  user: Omit<User, 'updatedAt'>;
}

// ─── Player (Roster CRM) ─────────────────────────────────────────────────────

export type PlayerStatus = 'active' | 'injured' | 'suspended' | 'graduated' | 'transferred' | 'walkOn';
export type AcademicYear = 'freshman' | 'sophomore' | 'junior' | 'senior' | 'graduate';
export type PositionGroup = 'QB' | 'RB' | 'WR' | 'TE' | 'OL' | 'DL' | 'LB' | 'DB' | 'K' | 'P' | 'LS' | 'ATH';

export interface Player {
  id: string;
  userId: string;
  jerseyNumber: number;
  firstName: string;
  lastName: string;
  position: PositionGroup;
  academicYear: AcademicYear;
  status: PlayerStatus;
  heightInches: number;
  weightLbs: number;
  homeTown: string;
  homeState: string;
  highSchool: string;
  recruitingClass: number;
  gpa?: number;
  major?: string;
  phone?: string;
  emergencyContactName?: string;
  emergencyContactPhone?: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export interface GraduationRequest {
  playerIds: string[];
  graduationYear: number;
  graduationSemester: 'spring' | 'fall' | 'summer';
  notes?: string;
  confirmedBy: string;
}

export interface GraduationResult {
  success: boolean;
  graduatedCount: number;
  failures: Array<{ playerId: string; reason: string }>;
  transactionId: string;
}

// ─── Alumni (Alumni CRM) ──────────────────────────────────────────────────────

export type AlumniStatus = 'active' | 'lostContact' | 'deceased' | 'doNotContact';
export type OutreachStatus = 'pending' | 'sent' | 'responded' | 'bounced' | 'unsubscribed';

export interface Alumni {
  id: string;
  userId: string;
  playerId: string;
  firstName: string;
  lastName: string;
  graduationYear: number;
  graduationSemester: 'spring' | 'fall' | 'summer';
  position: PositionGroup;
  recruitingClass: number;
  status: AlumniStatus;
  currentEmployer?: string;
  currentJobTitle?: string;
  currentCity?: string;
  currentState?: string;
  personalEmail?: string;
  phone?: string;
  linkedInUrl?: string;
  isDonor: boolean;
  lastDonationDate?: string;
  totalDonations?: number;
  engagementScore?: number;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export interface OutreachCampaign {
  id: string;
  name: string;
  description?: string;
  targetAudience: 'all' | 'byClass' | 'byPosition' | 'byStatus' | 'custom';
  audienceFilters?: Record<string, unknown>;
  status: 'draft' | 'scheduled' | 'active' | 'completed' | 'cancelled';
  scheduledAt?: string;
  completedAt?: string;
  createdBy: string;
  createdAt: string;
}

export interface OutreachMessage {
  id: string;
  campaignId: string;
  alumniId: string;
  channel: 'email' | 'sms' | 'push';
  status: OutreachStatus;
  sentAt?: string;
  openedAt?: string;
  respondedAt?: string;
  content?: string;
}

// ─── API Responses ────────────────────────────────────────────────────────────

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface PaginatedResponse<T> extends ApiResponse<T[]> {
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

export interface ApiError {
  success: false;
  error: string;
  code?: string;
  details?: unknown;
}

// ─── Sport Management ─────────────────────────────────────────────────────────

export interface Sport {
  id:          string;
  name:        string;
  abbr:        string;
  colorOverride?: string;
  customFields?: Record<string, unknown>;
  createdAt:   string;
}

// ─── Sport-Scoped Role Model ──────────────────────────────────────────────────
// Replaces app-scoped permissions. Each role assignment is per-sport within a tenant.

export type StarterRole =
  | 'account_owner'       // Billing / platform config — NOT a data role
  | 'coach_admin'         // Full roster + alumni access within their sport(s)
  | 'roster_only_admin';  // Roster data only — cannot see alumni

export interface UserSportRole {
  userId:    string;
  sportId:   string;
  sportName: string;
  role:      StarterRole;
  grantedAt: string;
  grantedBy: string;
}

// ─── User Classification (enforces player/alumni wall) ────────────────────────
export type UserClassification = 'roster' | 'alumni';

// ─── Season Management ────────────────────────────────────────────────────────

export type SeasonStatus = 'upcoming' | 'active' | 'completed' | 'archived';

export interface Season {
  id:        string;
  sportId:   string;
  name:      string;
  startDate: string;
  endDate:   string;
  status:    SeasonStatus;
  createdAt: string;
  updatedAt: string;
}

// ─── Announcements (Broadcast CRM — Starter Tier) ─────────────────────────────

export type AnnouncementAudience = 'roster' | 'alumni' | 'all';

export interface Announcement {
  id:             string;
  sportId:        string;
  title:          string;
  body:           string;
  targetAudience: AnnouncementAudience;
  createdBy:      string;
  createdAt:      string;
}

// ─── Updated Alumni type additions ────────────────────────────────────────────
// communicationConsent: must be true to receive emails/notifications (CAN-SPAM)
// originalPlayerId:     links back to the roster record this alumni was created from
// yearsOnRoster:        e.g. "2018-2022"
// city / state:         current location (Starter tier — alumni can self-edit)

export interface AlumniExtended extends Alumni {
  sportId:              string;
  userClassification:   UserClassification;    // always 'alumni'
  communicationConsent: boolean;
  originalPlayerId?:    string;                // FK to roster.players
  yearsOnRoster?:       string;               // e.g. "2018-2022"
  city?:                string;
  state?:               string;
}

// ─── Updated Player type additions ────────────────────────────────────────────

export interface PlayerExtended extends Player {
  sportId:            string;
  userClassification: UserClassification;    // always 'roster'
}
