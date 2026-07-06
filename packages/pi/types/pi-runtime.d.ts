// Ambient type shim — @earendil-works/pi-coding-agent is provided by the pi
// runtime (declared as peerDependency, not bundled). This declaration lets
// local tooling (LSP, tsconfig) resolve the module without installing it.
// The real types ship with pi; this is a minimal subset for the extension.

declare module "@earendil-works/pi-coding-agent" {
  export interface ExtensionContext {
    ui: {
      notify(message: string, severity: "info" | "warn" | "error"): void;
      confirm(title: string, body: string): Promise<boolean>;
    };
  }

  export interface ExtensionAPI {
    registerCommand(
      name: string,
      options: {
        description: string;
        handler: (args: string, ctx: ExtensionContext) => Promise<void> | void;
      },
    ): void;
  }
}
