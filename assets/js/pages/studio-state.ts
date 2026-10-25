import type { Vault } from "../lib/keystore.js";
import type {
  AccessSnapshot,
  DirectoryEntry,
  IdentityDetails,
  SignedEnvelope,
  UploadSession,
} from "../lib/models.js";

export type StudioView =
  | "overview"
  | "profile"
  | "projects"
  | "resources"
  | "collaboration"
  | "keys"
  | "history";
export type Act = (
  type: string,
  body: Record<string, any>,
  options?: {
    after?: () => void | Promise<void>;
    prepare?: () => void | Promise<void>;
  },
) => Promise<boolean>;
export type Can = (action: string, resource: string) => boolean;
export type Say = (message: string, kind?: string) => void;
export type FileFields = {
  path: string;
  project_id: string | null;
  media_type: string;
  meta: Record<string, string>;
  id?: string;
};
export type PublishFile = (file: File, fields: FileFields) => Promise<boolean>;
export type StudioState = {
  vault: Vault | null;
  signerId: string | null;
  authId: string | null;
  me: UploadSession | null;
  current: string | null;
  data: IdentityDetails | null;
  directory: DirectoryEntry[];
  access: AccessSnapshot | null;
  projectId: string | null;
  view: StudioView;
  busy: boolean;
  message: { text: string; kind: string } | null;
  events: SignedEnvelope[] | null;
  loading: boolean;
  directoryError: string | null;
};
