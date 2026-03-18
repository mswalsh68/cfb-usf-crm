// ─── Roles & Permissions ────────────────────────────────────────────────────

export type AppName = 'roster' | 'alumni' | 'global-admin';

export type GlobalRole =
  | 'global_admin'    // Full access to everything, all apps
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
  sub: string;            // user id
  email: string;
  globalRole: GlobalRole;
  appPermissions: AppPermission[];
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
  userId: string;           // links to global users table
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
  recruitingClass: number;  // year
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
  confirmedBy: string;      // userId of coach/admin triggering
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
  userId: string;           // links to global users table
  playerId: string;         // original roster player id
  firstName: string;
  lastName: string;
  graduationYear: number;
  graduationSemester: 'spring' | 'fall' | 'summer';
  position: PositionGroup;
  recruitingClass: number;
  status: AlumniStatus;
  // Post-grad info
  currentEmployer?: string;
  currentJobTitle?: string;
  currentCity?: string;
  currentState?: string;
  personalEmail?: string;
  phone?: string;
  linkedInUrl?: string;
  // Giving/engagement
  isDonor: boolean;
  lastDonationDate?: string;
  totalDonations?: number;
  engagementScore?: number; // 0-100
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
