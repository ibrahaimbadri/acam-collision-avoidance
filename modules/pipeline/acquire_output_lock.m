function cleanup = acquire_output_lock(output_dir, owner)
%ACQUIRE_OUTPUT_LOCK Refuse to write an output directory another run owns.
%
% The boundary calibration pilot was produced by two processes writing the
% same output directory concurrently. They interleaved their progress logs
% and collided on the shared checkpoint temporary file, which failed with a
% corruption error after both had completed all sixty scenarios. The results
% survived only because the computation is deterministic and both runs had
% identical frozen inputs. That is luck, not design.
%
% NO AGE-BASED RECLAMATION. An earlier version treated a lock older than a
% fixed age as abandoned, which reintroduced the exact failure it was meant
% to prevent: a run legitimately exceeding that age would have its lock
% deleted by a second writer, both would then write concurrently, and the
% first to finish would delete the second's lock and admit a third. Runs
% here can exceed any threshold worth setting, so every existing lock is
% treated as ACTIVE and must be removed by hand after confirming no MATLAB
% process owns the directory.
%
% Each lock carries a unique ownership token. Cleanup deletes the lock only
% while that token still matches, so a process can never release a lock it
% does not own.
%
% This is an ADVISORY lock, not a mutex. It closes the failure mode that
% actually occurred, a second launch after the first, and it does not close
% a genuine simultaneous-creation race, because MATLAB has no portable
% atomic exclusive-create. The remaining window is microseconds wide and the
% realistic adversary is a human pressing enter twice.
%
% Returns an onCleanup object. Keep it alive in the caller; the lock is
% released when it goes out of scope, including on error.

    if nargin < 2 || isempty(owner)
        owner = 'unknown';
    end
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    lock_path = fullfile(output_dir, '.output_writer.lock');

    if exist(lock_path, 'file')
        held = read_lock(lock_path);
        error('ACAM:OutputDirectoryLocked', ...
              ['%s is locked by "%s" (created %s). Refusing to start a ', ...
               'second writer.\nLocks are never reclaimed automatically, ', ...
               'because a long run would otherwise have its lock stolen ', ...
               'mid-flight. If no MATLAB process is writing this ', ...
               'directory, confirm that first, then delete %s by hand.'], ...
              output_dir, held.owner, held.created, lock_path);
    end

    % Unique per acquisition. tempname is used rather than rand so that
    % acquiring a lock cannot perturb a caller's seeded random stream.
    [~, unique_part] = fileparts(tempname);
    token = sprintf('%s-%s', unique_part, ...
                    char(datetime('now', 'Format', 'yyyyMMddHHmmssSSS')));

    file = fopen(lock_path, 'w');
    if file < 0
        error('ACAM:OutputLockNotWritable', ...
              'Could not create the output lock at %s.', lock_path);
    end
    fprintf(file, 'owner=%s\ncreated=%s\ntoken=%s\n', owner, ...
            char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), token);
    fclose(file);
    cleanup = onCleanup(@() release_lock(lock_path, token));
end

function held = read_lock(lock_path)
    held = struct('owner', 'unknown', 'created', 'unknown', 'token', '');
    try
        text = fileread(lock_path);
        held.owner = field_value(text, 'owner', held.owner);
        held.created = field_value(text, 'created', held.created);
        held.token = field_value(text, 'token', held.token);
    catch
        % An unreadable lock is still a lock. It is reported as held with
        % unknown fields rather than being treated as absent.
    end
end

function value = field_value(text, name, default_value)
    match = regexp(text, [name, '=([^\n\r]*)'], 'tokens', 'once');
    if isempty(match)
        value = default_value;
    else
        value = strtrim(match{1});
    end
end

function release_lock(lock_path, token)
%RELEASE_LOCK Delete the lock only while this process still owns it.
    if ~exist(lock_path, 'file')
        return;
    end
    held = read_lock(lock_path);
    if strcmp(held.token, token)
        delete(lock_path);
        return;
    end
    warning('ACAM:OutputLockNotOwned', ...
            ['Not releasing %s: it is now held by "%s" with a different ', ...
             'token. Another writer owns this directory.'], ...
            lock_path, held.owner);
end
