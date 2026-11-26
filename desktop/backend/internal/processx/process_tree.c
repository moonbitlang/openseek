// Windows-only: contain a spawned process's whole tree in a Job Object so it
// can be terminated as a unit (see `process_tree.mbt`). On other platforms this
// file compiles to nothing.

#ifdef _WIN32

#include <windows.h>
#include <tlhelp32.h>
#include <stdint.h>
#include <string.h>
#include <moonbit.h>

// Upper bound on the descendants adopted by the post-assignment sweep, which
// only has to catch processes started before containment (such as `moonx` and
// its child `moonrun`). Anything the tree starts after containment lands in
// the job without a sweep.
#define PROCESS_TREE_MAX 64

#define PROCESS_TREE_ACCESS \
  (PROCESS_SET_QUOTA | PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION)

static ULONGLONG process_tree_creation_time(HANDLE process) {
  FILETIME creation, exit_time, kernel, user;
  if (!GetProcessTimes(process, &creation, &exit_time, &kernel, &user))
    return 0;
  return ((ULONGLONG)creation.dwHighDateTime << 32) | creation.dwLowDateTime;
}

// Adopt descendants the root started before it was assigned to `job`: once the
// root is in the job its new children inherit it, but one spawned in the
// window between `CreateProcess` and `AssignProcessToJobObject` is outside.
// A process counts as a child of a tree member only if it was created after
// that member, which rejects a stale parent PID that was reused.
static void process_tree_adopt_descendants(
  HANDLE job,
  DWORD root_pid,
  ULONGLONG root_created
) {
  DWORD pids[PROCESS_TREE_MAX];
  ULONGLONG created[PROCESS_TREE_MAX];
  int count = 0;
  pids[count] = root_pid;
  created[count] = root_created;
  count++;

  // An adopted child may itself have started a process before it joined the
  // job, after the snapshot it was found in was taken. So keep taking fresh
  // snapshots until one adopts nothing: by then every tree member is in the
  // job, and anything they start later inherits it.
  int adopted = 1;
  while (adopted && count < PROCESS_TREE_MAX) {
    adopted = 0;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
      return;
    // Snapshot order is not parent-before-child, so repeat passes until one
    // adopts nothing new.
    int grew = 1;
    while (grew && count < PROCESS_TREE_MAX) {
      grew = 0;
      PROCESSENTRY32W entry;
      entry.dwSize = sizeof(entry);
      if (!Process32FirstW(snapshot, &entry))
        break;
      do {
        int parent = -1;
        int known = 0;
        for (int i = 0; i < count; ++i) {
          if (pids[i] == entry.th32ProcessID) {
            known = 1;
            break;
          }
          if (pids[i] == entry.th32ParentProcessID)
            parent = i;
        }
        if (known || parent < 0)
          continue;
        HANDLE child =
          OpenProcess(PROCESS_TREE_ACCESS, FALSE, entry.th32ProcessID);
        if (child == NULL)
          continue;
        ULONGLONG child_created = process_tree_creation_time(child);
        if (child_created != 0 && child_created >= created[parent]) {
          // Best effort: a child that cannot join the job is still recorded
          // so its own descendants are considered.
          AssignProcessToJobObject(job, child);
          pids[count] = entry.th32ProcessID;
          created[count] = child_created;
          count++;
          grew = 1;
          adopted = 1;
        }
        CloseHandle(child);
      } while (count < PROCESS_TREE_MAX && Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
  }
}

// Create a job that kills its members when its last handle closes, assign the
// process `pid` (and any descendants it already has) to it, and return the job
// handle, or 0 when containment is unavailable. The job deliberately does not
// allow breakaway, so children the tree starts later stay inside it even
// though the async runtime's own job permits silent breakaway.
MOONBIT_FFI_EXPORT
uint64_t openseek_desktop_process_tree_contain(int32_t pid) {
  HANDLE job = CreateJobObjectW(NULL, NULL);
  if (job == NULL)
    return 0;

  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info;
  memset(&info, 0, sizeof(info));
  info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (
    !SetInformationJobObject(
      job,
      JobObjectExtendedLimitInformation,
      &info,
      sizeof(info)
    )
  ) {
    CloseHandle(job);
    return 0;
  }

  HANDLE root = OpenProcess(PROCESS_TREE_ACCESS, FALSE, (DWORD)pid);
  if (root == NULL) {
    CloseHandle(job);
    return 0;
  }
  // The root is already in the async runtime's job; on Windows 8+ this nests
  // the new (empty) job under it.
  if (!AssignProcessToJobObject(job, root)) {
    CloseHandle(root);
    CloseHandle(job);
    return 0;
  }
  process_tree_adopt_descendants(job, (DWORD)pid, process_tree_creation_time(root));
  CloseHandle(root);
  return (uint64_t)(uintptr_t)job;
}

// Terminate every process still in the job and release it.
MOONBIT_FFI_EXPORT
void openseek_desktop_process_tree_terminate(uint64_t job) {
  HANDLE handle = (HANDLE)(uintptr_t)job;
  TerminateJobObject(handle, 1);
  CloseHandle(handle);
}

#else

// Keep this translation unit non-empty for strict compilers.
typedef int openseek_desktop_process_tree_unused;

#endif
