% script startup.m
%
% This is a template startup.m file.
%
% STEPS TO SETUP MATLAB ENVIRONMENT ARE ON WIKI:
%   https://gitlab.com/openpolarradar/opr/-/wikis/home
%
% Step 1
%  Rename this file to startup.m and save in the folder returned by the "userpath" Matlab command.
%  You can also set the user path like this: userpath('/scratch/scripts/matlab') and then place
%  startup.m in that folder.
%
% Step 2
%  Modify one of the profiles below and set cur_profile to this profile.
%  Often no changes are necessary and the default paths for one of the
%  profiles below will work well
%
% Step 3
%  Run "startup" from Matlab; it should run this script if the userpath
%  and startup.m are set up correctly.
%
% Authors: John Paden

if ~(~ismcc && isdeployed)
  
  %% ===> SELECT CURRENT PROFILE HERE <===
  % cur_profile: Set the current profile to load (match to pidx below)
  % Profile Windows (PROFILE 1)
  % Profile Linux/Mac (PROFILE 2)
  % KU Profile Linux (PROFILE 3)
  % KU Field Profile Linux (PROFILE 4)
  % KU Desktop Profile Windows (PROFILE 5)
  % IU Profile Linux (PROFILE 6)
  % AWI Profile Field Windows (PROFILE 7)
  % OPR Workshop Profile Linux (PROFILE 8)
  % AWI Profile Ollie (PROFILE 9)
  if ispc
    cur_profile = 5; % Put your default Windows profile here
  else
    cur_profile = 3; % Put your default Linux/Mac profile here
  end
  
  fprintf('Startup Script Running: %s\n', mfilename('fullpath'));
  
  format short; format compact;
  profile = [];

  %% Profile Windows (PROFILE 1)
  % ----------------------------------------------------------------------
  pidx = 1; % profile index
  base_dir = fullfile(getenv('USERPROFILE'),'My Documents','scripts');
  %base_dir = 'C:\git\';
  profile(pidx).path_override             = fullfile(base_dir,'run_opr');
  profile(pidx).path                      = fullfile(base_dir,'opr','matlab');
  profile(pidx).param_path                = fullfile(base_dir,'opr_params');
  profile(pidx).tmp_file_path             = fullfile(base_dir,'opr_user_tmp');

  base_dir = 'C:\';
  profile(pidx).data_path                 = fullfile(base_dir);
  profile(pidx).data_support_path         = fullfile(base_dir,'metadata');
  profile(pidx).support_path              = fullfile(base_dir,'opr_support');
  profile(pidx).out_path                  = fullfile(base_dir);
  profile(pidx).gis_path                  = fullfile(base_dir,'GIS_data');

  profile(pidx).opr_tmp_file_path          = fullfile(profile(pidx).out_path,'opr_tmp'); 
  profile(pidx).cluster.data_location     = fullfile(profile(pidx).tmp_file_path,'cluster');
  
  profile(pidx).cluster.type                  = 'matlab';
  %profile(pidx).cluster.type                  = 'debug';
  profile(pidx).cluster.max_jobs_active       = 4;
  profile(pidx).cluster.max_time_per_job      = 2*86400;
  profile(pidx).cluster.desired_time_per_job  = 0;
  profile(pidx).cluster.max_retries           = 1;
  profile(pidx).cluster.submit_pause          = 0;
  profile(pidx).cluster.stat_pause            = 1;
  
  profile(pidx).ops.url = 'https://ops.cresis.ku.edu/'; % Read-only for outside of CReSIS
  profile(pidx).ops.google_map_api_key = 'AIzaSyCNexiP6WcIda8ZEa2MnwznWrGotDoLu0w'; % Fill in with your Google API key (see google.m)
  profile(pidx).data.url = 'https://data.cresis.ku.edu/';
  
  
  %% Profile Linux/Mac (PROFILE 2)
  % ----------------------------------------------------------------------
  pidx = 2; % profile index
  base_dir = fullfile(getenv('HOME'),'scripts');
  profile(pidx).path_override             = fullfile(base_dir,'run_opr');
  profile(pidx).path                      = fullfile(base_dir,'opr','matlab');
  profile(pidx).param_path                = fullfile(base_dir,'opr_params');
  profile(pidx).tmp_file_path             = fullfile(base_dir,'opr_user_tmp');

  base_dir = fullfile(getenv('HOME'),'scratch');
  profile(pidx).data_path                 = fullfile(base_dir);
  profile(pidx).data_support_path         = fullfile(base_dir,'metadata');
  profile(pidx).support_path              = fullfile(base_dir,'opr_support');
  profile(pidx).out_path                  = fullfile(base_dir);
  profile(pidx).gis_path                  = fullfile(base_dir,'GIS_data');

  profile(pidx).opr_tmp_file_path          = fullfile(profile(pidx).out_path,'opr_tmp'); 
  profile(pidx).cluster.data_location     = fullfile(profile(pidx).tmp_file_path,'cluster');

  profile(pidx).cluster.type                    = 'matlab';
  %profile(pidx).cluster.type                    = 'slurm';
  %profile(pidx).cluster.type                    = 'ollie';
  %profile(pidx).cluster.type                    = 'debug';
  profile(pidx).cluster.max_jobs_active         = 128;
  profile(pidx).cluster.max_time_per_job        = 2*86400;
  profile(pidx).cluster.desired_time_per_job    = 2*3600;
  profile(pidx).cluster.max_retries             = 2;
  profile(pidx).cluster.submit_pause            = 0.2;
  profile(pidx).cluster.stat_pause              = 2;
  profile(pidx).cluster.file_check_pause        = 4;
  profile(pidx).cluster.ld_library_path        = ''; % Override Matlab's library path when running commands like "gs" (ghostscript) from post.m
  
  profile(pidx).ops.url = 'https://ops.cresis.ku.edu/'; % Read-only for outside of CReSIS
  profile(pidx).ops.google_map_api_key = 'AIzaSyCNexiP6WcIda8ZEa2MnwznWrGotDoLu0w'; % Fill in with your Google API key
  profile(pidx).data.url = 'https://data.cresis.ku.edu/';
  
  
  %% KU Profile Linux (PROFILE 3)
  % ----------------------------------------------------------------------
  pidx = 3; % profile index
  base_dir = fullfile('/cresis/users/',getenv('USER'),'scripts');
  % base_dir = fullfile('/cresis/raid_nvmescratch/',getenv('USER'),'scripts');
  profile(pidx).path_override             = fullfile(base_dir,'run_opr');
  profile(pidx).path                      = fullfile(base_dir,'opr','matlab');
  profile(pidx).param_path                = fullfile(base_dir,'opr_params');
  profile(pidx).tmp_file_path             = fullfile(base_dir,'opr_user_tmp');

  profile(pidx).data_path                 = '/cresis/data/';
  base_dir = '/cresis/dataproducts/';
  profile(pidx).out_path                  = fullfile(base_dir,'opr_data');
  base_dir = '/resfs/GROUPS/CRESIS/dataproducts/';
  profile(pidx).data_support_path         = fullfile(base_dir,'metadata');
  profile(pidx).support_path              = fullfile(base_dir,'opr_support');
  profile(pidx).gis_path                  = fullfile(base_dir,'GIS_data');

  profile(pidx).personal_path                 = '/kucresis/scratch/nholschuh_sta/scripts/NDH_MatlabTools';

  profile(pidx).opr_tmp_file_path          = fullfile(profile(pidx).out_path,'opr_tmp'); 
  profile(pidx).cluster.data_location     = fullfile(profile(pidx).tmp_file_path,'cluster');
  
  profile(pidx).cluster.type                  = 'slurm';
  %profile(pidx).cluster.type                  = 'matlab';
  %profile(pidx).cluster.type                  = 'debug';
  profile(pidx).cluster.max_jobs_active       = 96;
  profile(pidx).cluster.max_time_per_job      = 2*86400;
  profile(pidx).cluster.desired_time_per_job  = 0;
  profile(pidx).cluster.max_retries           = 2;
  profile(pidx).cluster.submit_pause          = 0.2;
  profile(pidx).cluster.stat_pause            = 2;
  profile(pidx).cluster.file_check_pause      = 4;
  profile(pidx).cluster.job_complete_pause    = 60;
  profile(pidx).cluster.mem_to_ppn            = 0.9 * 250e9 / 24;
  profile(pidx).cluster.max_ppn               = 4;
  profile(pidx).cluster.max_mem_per_job       = 250e9;
  profile(pidx).cluster.mem_mult_mode         = 'auto';
  profile(pidx).cluster.max_cpu_time_mode     = 'truncate';
  profile(pidx).cluster.max_mem_mode          = 'truncate';

  profile(pidx).cluster.slurm_submit_arguments = '-N 1 -n 1 --cpus-per-task=%p --mem=%m --time=%t';
  %profile(pidx).cluster.cpu_time_mult         = 2;
  %profile(pidx).cluster.mem_mult              = 2;
  %profile(pidx).cluster.ppn_fixed             = 4;
  profile(pidx).cluster.matlab_mcr_path        = '/kucresis/scratch/software/matlab/MCR_install/R2024b/';
  % Override LD_LIBRARY_PATH variable (only used by system call to gs in post.m)
  profile(pidx).cluster.ld_library_path        = '/panfs/pfs.local/software/7/install/openmpi/4.0/gcc/8.3/lib:/panfs/pfs.local/software/7/install/binutils/2.32/lib:/panfs/pfs.local/software/7/install/gcc/8.3/lib64:/panfs/pfs.local/software/7/install/gcc/8.3/lib:/opt/thinlinc/lib64:/opt/thinlinc/lib';

  profile(pidx).ops.url = 'https://ops.cresis.ku.edu/'; % Read-only for outside of CReSIS
  profile(pidx).ops.google_map_api_key = 'AIzaSyCNexiP6WcIda8ZEa2MnwznWrGotDoLu0w'; % Fill in with your Google API key
  profile(pidx).data.url = 'https://data.cresis.ku.edu/';
  
  % docroot('/opt/sw/matlab/SupportPackages/R2024b/help'); % Optionally use local matlab help install instead of internet.
  
  %% KU Field Profile Linux (PROFILE 4)
  % ----------------------------------------------------------------------
  pidx = 4; % profile index
  base_dir = '/scratch/scripts/';
  profile(pidx).path_override             = fullfile(base_dir,'run_opr');
  profile(pidx).path                      = fullfile(base_dir,'opr','matlab');
  profile(pidx).param_path                = fullfile(base_dir,'opr_params');
  profile(pidx).tmp_file_path             = fullfile(base_dir,'opr_user_tmp');

  base_dir = '/scratch/';
  profile(pidx).data_path                 = fullfile(base_dir);
  profile(pidx).gis_path                  = fullfile(base_dir,'GIS_data');
  profile(pidx).data_support_path         = fullfile(base_dir,'metadata');
  profile(pidx).support_path              = fullfile(base_dir,'opr_support');
  profile(pidx).out_path                  = fullfile(base_dir);
  profile(pidx).opr_tmp_file_path          = fullfile(profile(pidx).out_path,'opr_tmp'); 
  profile(pidx).cluster.data_location     = fullfile(profile(pidx).tmp_file_path,'cluster');
  
  %profile(pidx).cluster.type                  = 'slurm';
  profile(pidx).cluster.type                  = 'matlab';
  %profile(pidx).cluster.type                  = 'debug';
  profile(pidx).cluster.max_jobs_active       = 128;
  profile(pidx).cluster.max_time_per_job      = 2*86400;
  profile(pidx).cluster.desired_time_per_job  = 0;
  profile(pidx).cluster.max_retries           = 2;
  profile(pidx).cluster.submit_pause          = 0.2;
  profile(pidx).cluster.stat_pause            = 2;
  profile(pidx).cluster.file_check_pause      = 4;
  profile(pidx).cluster.mem_to_ppn            = 0.9 * 131754468000 / 46;
  profile(pidx).cluster.max_ppn               = 6;
  profile(pidx).cluster.job_complete_pause    = 5;
  profile(pidx).cluster.max_mem_per_job       = 126e9;
  profile(pidx).cluster.mem_mult_mode          = 'debug';
  profile(pidx).cluster.ld_library_path        = ''; % Override Matlab's library path when running commands like "gs" (ghostscript) from post.m

  profile(pidx).ops.url = 'https://ops.cresis.ku.edu/'; % Read-only for outside of CReSIS
  profile(pidx).ops.google_map_api_key = 'AIzaSyCNexiP6WcIda8ZEa2MnwznWrGotDoLu0w'; % Fill in with your Google API key
  profile(pidx).data.url = 'https://data.cresis.ku.edu/';  
  
  %% KU Desktop Profile Windows (PROFILE 5)
  % ----------------------------------------------------------------------
  pidx = 5; % profile index
  base_dir = fullfile(getenv('USERPROFILE'),'My Documents','scripts');
  %base_dir = 'C:\git\';
  profile(pidx).path_override             = fullfile(base_dir,'run_opr');
  profile(pidx).path                      = fullfile(base_dir,'opr','matlab');
  profile(pidx).param_path                = fullfile(base_dir,'opr_params');
  profile(pidx).tmp_file_path             = fullfile(base_dir,'opr_user_tmp');

  profile(pidx).data_path                 = 'Z:\';
  base_dir = 'X:\';
  profile(pidx).gis_path                  = fullfile(base_dir,'GIS_data');
  profile(pidx).data_support_path         = fullfile(base_dir,'metadata');
  profile(pidx).support_path              = fullfile(base_dir,'opr_support');
  base_dir = 'Y:\dataproducts\';
  profile(pidx).out_path                  = fullfile(base_dir,'opr_data');
  profile(pidx).opr_tmp_file_path          = fullfile(profile(pidx).out_path,'opr_tmp');
  profile(pidx).cluster.data_location     = fullfile(profile(pidx).tmp_file_path,'cluster');
  
  profile(pidx).cluster.type                  = 'matlab';
  %profile(pidx).cluster.type                  = 'debug';
  profile(pidx).cluster.max_jobs_active       = 4;
  profile(pidx).cluster.max_time_per_job      = 2*86400;
  profile(pidx).cluster.desired_time_per_job  = 0;
  profile(pidx).cluster.max_retries           = 1;
  profile(pidx).cluster.submit_pause          = 0;
  profile(pidx).cluster.stat_pause            = 1;

  profile(pidx).ops.url = 'https://ops.cresis.ku.edu/'; % Read-only for outside of CReSIS
  profile(pidx).ops.google_map_api_key = 'AIzaSyCNexiP6WcIda8ZEa2MnwznWrGotDoLu0w'; % Fill in with your Google API key
  profile(pidx).data.url = 'https://data.cresis.ku.edu/';  
  
  %% IU Profile Linux (PROFILE 6)
  % ----------------------------------------------------------------------
  pidx = 6; % profile index
  base_dir = fullfile(getenv('HOME'),'scripts');
  profile(pidx).path_override             = fullfile(base_dir,'run_opr');
  profile(pidx).path                      = fullfile(base_dir,'opr','matlab');
  profile(pidx).param_path                = fullfile(base_dir,'opr_params');
  profile(pidx).tmp_file_path             = fullfile(base_dir,'opr_user_tmp');

  base_dir = '/N/dcwan/projects/cresis/';
  profile(pidx).data_path                 = fullfile(base_dir);
  profile(pidx).data_support_path         = fullfile(base_dir,'metadata');
  profile(pidx).support_path              = fullfile(base_dir,'opr_support');
  profile(pidx).out_path                  = fullfile(base_dir);
  profile(pidx).gis_path                  = fullfile(base_dir,'GIS_data');

  profile(pidx).opr_tmp_file_path          = fullfile(profile(pidx).out_path,'opr_tmp'); 
  profile(pidx).cluster.data_location     = fullfile(profile(pidx).tmp_file_path,'cluster');
  
  %profile(pidx).cluster.type                  = 'slurm';
  %profile(pidx).cluster.type                  = 'torque';
  %profile(pidx).cluster.type                  = 'matlab';
  profile(pidx).cluster.type                  = 'debug';
  if 0
    profile(pidx).cluster.ssh_hostname          = 'karst.uits.iu.edu';
    profile(pidx).cluster.mem_to_ppn            = 0.9 * 32e9 / 16;
    profile(pidx).cluster.max_ppn               = 8;
    profile(pidx).cluster.max_mem_per_job       = 30e9;
    profile(pidx).cluster.mem_mult_mode          = 'debug';
  else
    profile(pidx).cluster.mem_to_ppn            = 0.9 * 256e9 / 24;
    profile(pidx).cluster.max_ppn               = 12;
    profile(pidx).cluster.max_mem_per_job       = 250e9;
    profile(pidx).cluster.mem_mult_mode          = 'auto';
  end
  profile(pidx).cluster.max_jobs_active       = 512;
  profile(pidx).cluster.max_time_per_job      = 4*86400;
  profile(pidx).cluster.desired_time_per_job  = 2*3600;
  profile(pidx).cluster.max_retries           = 2;
  profile(pidx).cluster.submit_pause          = 1;
  profile(pidx).cluster.stat_pause            = 10;
  profile(pidx).cluster.file_check_pause      = 0;

  profile(pidx).cluster.slurm_submit_arguments = '-N 1 -n 1 --cpus-per-task=%p --mem=%m --time=%t';
  %profile(pidx).cluster.slurm_submit_arguments = '-p debug -N 1 -n 1 --cpus-per-task=%p --mem=%m --time=%t';

  profile(pidx).ops.url = 'https://ops.cresis.ku.edu/'; % Read-only for outside of CReSIS
  profile(pidx).ops.google_map_api_key = 'AIzaSyCNexiP6WcIda8ZEa2MnwznWrGotDoLu0w'; % Fill in with your Google API key
  profile(pidx).data.url = 'https://data.cresis.ku.edu/';  
  
  
  %% AWI Profile Field Windows (PROFILE 7)
  % ----------------------------------------------------------------------
  pidx = 7; % profile index
  base_dir = 'S:\Scratch\scripts\';
  profile(pidx).path_override             = fullfile(base_dir,'run_opr');
  profile(pidx).path                      = fullfile(base_dir,'opr','matlab');
  profile(pidx).param_path                = fullfile(base_dir,'opr_params');
  profile(pidx).tmp_file_path             = fullfile(base_dir,'opr_user_tmp');

  base_dir = 'S:\Scratch\';
  profile(pidx).data_path                 = fullfile(base_dir);
  profile(pidx).data_support_path         = fullfile(base_dir,'metadata');
  profile(pidx).support_path              = fullfile(base_dir,'opr_support');
  profile(pidx).out_path                  = fullfile(base_dir);
  profile(pidx).gis_path                  = fullfile(base_dir,'GIS_data');

  profile(pidx).opr_tmp_file_path          = fullfile(profile(pidx).out_path,'opr_tmp'); 
  profile(pidx).cluster.data_location     = fullfile(profile(pidx).tmp_file_path,'cluster');

  profile(pidx).cluster.type                  = 'matlab';
  %profile(pidx).cluster.type                  = 'debug';
  profile(pidx).cluster.max_jobs_active       = 4;
  profile(pidx).cluster.max_time_per_job      = 2*86400;
  profile(pidx).cluster.desired_time_per_job  = 0;
  profile(pidx).cluster.max_retries           = 1;
  profile(pidx).cluster.submit_pause          = 0;
  profile(pidx).cluster.stat_pause            = 1;

  profile(pidx).ops.url = 'https://ops.cresis.ku.edu/'; % Read-only for outside of CReSIS
  profile(pidx).ops.google_map_api_key = 'AIzaSyCNexiP6WcIda8ZEa2MnwznWrGotDoLu0w'; % Fill in with your Google API key
  profile(pidx).data.url = 'https://data.cresis.ku.edu/';  
  
  %% OPR Workshop Profile Linux (PROFILE 8)
  % ----------------------------------------------------------------------
  pidx = 8; % profile index
  base_dir = fullfile(getenv('HOME'),'scripts');
  profile(pidx).path_override             = fullfile(base_dir,'run_opr');
  profile(pidx).path                      = fullfile(base_dir,'opr','matlab');
  profile(pidx).param_path                = fullfile(base_dir,'opr_params');
  profile(pidx).tmp_file_path             = fullfile(base_dir,'opr_user_tmp');

  profile(pidx).data_path                 = '/kucresis/scratch/data/';
  base_dir = '/kucresis/scratch/dataproducts/';
  profile(pidx).out_path                  = fullfile(base_dir,'opr_data');
  base_dir = '/resfs/GROUPS/CRESIS/dataproducts/';
  profile(pidx).data_support_path         = fullfile(base_dir,'metadata');
  profile(pidx).support_path              = fullfile(base_dir,'opr_support');
  profile(pidx).gis_path                  = fullfile(base_dir,'GIS_data');

  profile(pidx).opr_tmp_file_path         = fullfile(profile(pidx).out_path,'opr_tmp'); 
  profile(pidx).cluster.data_location     = fullfile(profile(pidx).tmp_file_path,'cluster');
  
  %profile(pidx).cluster.type                  = 'slurm';
  %profile(pidx).cluster.type                  = 'matlab';
  profile(pidx).cluster.type                  = 'debug';
  profile(pidx).cluster.max_jobs_active       = 96;
  profile(pidx).cluster.max_time_per_job      = 2*86400;
  profile(pidx).cluster.desired_time_per_job  = 0;
  profile(pidx).cluster.max_retries           = 2;
  profile(pidx).cluster.submit_pause          = 0.2;
  profile(pidx).cluster.stat_pause            = 2;
  profile(pidx).cluster.file_check_pause      = 4;
  profile(pidx).cluster.job_complete_pause    = 60;
  profile(pidx).cluster.mem_to_ppn            = 0.9 * 250e9 / 24;
  profile(pidx).cluster.max_ppn               = 4;
  profile(pidx).cluster.max_mem_per_job       = 250e9;
  profile(pidx).cluster.mem_mult_mode          = 'debug';
  profile(pidx).cluster.slurm_submit_arguments = '--partition=cresis -N 1 -n 1 --cpus-per-task=%p --mem=%m --time=%t';
  %profile(pidx).cluster.cpu_time_mult         = 2;
  %profile(pidx).cluster.mem_mult              = 2;
  %profile(pidx).cluster.ppn_fixed             = 4;
  profile(pidx).cluster.matlab_mcr_path        = '/kucresis/scratch/software/matlab/MCR_install/R2024b/';
  % Override LD_LIBRARY_PATH variable (only used by system call to gs in post.m)
  profile(pidx).cluster.ld_library_path        = '/panfs/pfs.local/software/7/install/openmpi/4.0/gcc/8.3/lib:/panfs/pfs.local/software/7/install/binutils/2.32/lib:/panfs/pfs.local/software/7/install/gcc/8.3/lib64:/panfs/pfs.local/software/7/install/gcc/8.3/lib:/opt/thinlinc/lib64:/opt/thinlinc/lib';

  profile(pidx).ops.url = 'https://ops.cresis.ku.edu/'; % Read-only for outside of CReSIS
  profile(pidx).ops.google_map_api_key = 'AIzaSyCNexiP6WcIda8ZEa2MnwznWrGotDoLu0w'; % Fill in with your Google API key
  profile(pidx).data.url = 'https://data.cresis.ku.edu/';  
  
  % docroot('/opt/sw/matlab/SupportPackages/R2024b/help'); % Optionally use local matlab help install instead of internet.
  
  profile(pidx).mat_file_version = '-v7';

  %% AWI Profile Ollie (PROFILE 9)
  % ----------------------------------------------------------------------
  pidx = 9; % profile index
  base_dir = fullfile('/work/ollie',getenv('USER'),'scripts');
  profile(pidx).path_override             = fullfile(base_dir,'run_opr');
  profile(pidx).path                      = fullfile(base_dir,'opr','matlab');
  profile(pidx).param_path                = fullfile(base_dir,'opr_params');
  profile(pidx).tmp_file_path             = fullfile(base_dir,'opr_user_tmp');

  base_dir = fullfile('/work/ollie',getenv('USER'));
  profile(pidx).data_path                 = fullfile(base_dir);
  profile(pidx).data_support_path         = fullfile(base_dir,'metadata');
  profile(pidx).support_path              = fullfile(base_dir,'opr_support');
  profile(pidx).out_path                  = fullfile(base_dir);
  profile(pidx).gis_path                  = fullfile(base_dir,'GIS_data');

  profile(pidx).opr_tmp_file_path          = fullfile(profile(pidx).out_path,'opr_tmp'); 
  profile(pidx).cluster.data_location     = fullfile(profile(pidx).tmp_file_path,'cluster');

  profile(pidx).cluster.type                    = 'slurm';
  %profile(pidx).cluster.type                    = 'matlab';
  %profile(pidx).cluster.type                    = 'debug';
  profile(pidx).cluster.max_jobs_active         = 128;
  profile(pidx).cluster.max_time_per_job        = 2*86400;
  profile(pidx).cluster.desired_time_per_job    = 2*3600;
  profile(pidx).cluster.max_retries             = 2;
  profile(pidx).cluster.submit_pause            = 1;
  profile(pidx).cluster.stat_pause              = 10;
  profile(pidx).cluster.file_check_pause        = 4;
  profile(pidx).cluster.job_complete_pause      = 30;
  profile(pidx).cluster.mem_to_ppn              = 0.9 * 64e9 / 36;
  profile(pidx).cluster.max_ppn                 = 18;
  profile(pidx).cluster.max_mem_per_job         = 62e9;
  profile(pidx).cluster.mem_mult_mode            = 'debug';

  profile(pidx).cluster.mcc                     = 'system_eval';

  profile(pidx).ops.url = 'https://ops.cresis.ku.edu/'; % Read-only for outside of CReSIS
  profile(pidx).ops.google_map_api_key = 'AIzaSyCNexiP6WcIda8ZEa2MnwznWrGotDoLu0w'; % Fill in with your Google API key
  profile(pidx).data.url = 'https://data.cresis.ku.edu/';
  
  %% Startup code (Automated Section)
  % =====================================================================
  
  fprintf('  Resetting path\n');
  path(pathdef);
  AdditionalPaths = {};
  
  %%%%%%%%%%%%%% Added by NDH
  if exist(profile(cur_profile).personal_path)
      %disp(profile(cur_profile).personal_path)
  end
  if exist(profile(cur_profile).personal_path,'dir')
      disp('Adding Personal path')
      addpath(profile(cur_profile).personal_path)
      AdditionalPaths{end+1} = profile(cur_profile).personal_path;
  end
  %%%%%%%%%%%%%%%%%%%%%%%%%%%


  if ~exist(profile(cur_profile).path,'dir')
    fprintf('OPR toolbox not found: %s\n', profile(cur_profile).path);
  else
    fprintf('  Adding OPR toolbox path: %s\n',profile(cur_profile).path);
    % Add get_filenames to the path
    addpath(fullfile(profile(cur_profile).path));
    addpath(fullfile(profile(cur_profile).path,'utility'));
    % Add each directory which is not an svn support directory to the path
    fns = get_filenames(profile(cur_profile).path,'','','',struct('type','d','recursive',1));
    if ispc
      addpath(profile(cur_profile).path);
      AdditionalPaths{end+1} = profile(cur_profile).path;
    end
    for fn_idx = 1:length(fns)
      [fn_dir fn_name] = fileparts(fns{fn_idx});
      if ~isempty(fn_name) && fn_name(1) ~= '@' && fn_name(1) ~= '+' ...
          && isempty(strfind(fns{fn_idx},'.svn')) && isempty(strfind(fns{fn_idx},'.git'))
        % Ignore .svn directories and Matlab class and package directories
        addpath(fns{fn_idx});
        AdditionalPaths{end+1} = fns{fn_idx};
      end
    end
  end
  
  if ~exist(profile(cur_profile).path_override,'dir')
    fprintf('Personal toolbox not found: %s\n', profile(cur_profile).path_override);
  else
    % Add personal path after OPR path so that it overrides OPR paths
    fprintf('  Adding personal path: %s\n',profile(cur_profile).path_override);
    fns = get_filenames(profile(cur_profile).path_override,'','','',struct('type','d','recursive',1));
    addpath(profile(cur_profile).path_override);
    AdditionalPaths{end+1} = profile(cur_profile).path_override;
    for fn_idx = 1:length(fns)
      [fn_dir fn_name] = fileparts(fns{fn_idx});
      if ~isempty(fn_name) && fn_name(1) ~= '@' && fn_name(1) ~= '+' ...
          && isempty(strfind(fns{fn_idx},'.svn')) && isempty(strfind(fns{fn_idx},'.git'))
        % Ignore .svn directories and Matlab class and package directories
        addpath(fns{fn_idx});
        AdditionalPaths{end+1} = fns{fn_idx};
      end
    end
  end
  fprintf('  Setting global preferences in global variable gRadar\n');
  global gRadar;
  
  % .cluster: structure with default cluster scheduler arguments
  gRadar.cluster = profile(cur_profile).cluster;
  % .sched.hidden_depends_funs = cell vector of strings containing
  %   all the dependent functions that should be included when the
  %   torque_compile function is called. This list should only include
  %   functions which are passed in (e.g. "@hanning" from param spreadsheet)
  %   since all directly dependent functions will automatically be included.
  %   Second cell entry is date check level in torque_compile:
  %     0: do not check for this file (system commands)
  %     1: check this file and its dependencies (function pointers)
  %     2: check this file and its dependencies only if "fun" is not
  %        specified in call to torque_compile.m (all functions called
  %        by torque_compile)
  % =======================================================================
  % REMINDER: Run cluster_compile after making changes to this list!
  % =======================================================================
  gRadar.cluster.hidden_depend_funs = {};
  gRadar.cluster.hidden_depend_funs{end+1} = {'tomo_collate_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'analysis_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'analysis_combine_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'analysis_task_stats_max.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'analysis_task_stats_kx.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'qlook_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'qlook_combine_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'sar_coord_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'sar_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'array_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'array_combine_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'nsidc_delivery_script_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'preprocess_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'layer_tracker_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'layer_tracker_combine_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'polarimetric_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'sim_doa_task.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'default_radar_params_2022_Antarctica_BaslerMKB_rds.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'default_radar_params_2023_Antarctica_BaslerMKB_accum.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'default_radar_params_2015_Antarctica_LC130_rds.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'default_radar_params_2016_Antarctica_LC130_rds.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'default_radar_params_2017_Antarctica_LC130_rds.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'default_radar_params_2016_Antarctica_LC130_snow.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'default_radar_params_2023_Antarctica_Ground_accum.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'default_radar_params_2023_Antarctica_GroundGHOST_rds.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'default_radar_params_2023_Antarctica_GroundGHOST_snow.m' 2};
  gRadar.cluster.hidden_depend_funs{end+1} = {'hanning.m' 0};
  gRadar.cluster.hidden_depend_funs{end+1} = {'hamming.m' 0};
  gRadar.cluster.hidden_depend_funs{end+1} = {'blackman.m' 0};
  gRadar.cluster.hidden_depend_funs{end+1} = {'tukeywin.m' 0};
  gRadar.cluster.hidden_depend_funs{end+1} = {'tukeywin_trim.m' 1};
  gRadar.cluster.hidden_depend_funs{end+1} = {'chebwin.m' 0};
  gRadar.cluster.hidden_depend_funs{end+1} = {'kaiser.m' 0};
  gRadar.cluster.hidden_depend_funs{end+1} = {'boxcar.m' 0};
  gRadar.cluster.hidden_depend_funs{end+1} = {'butter.m' 0};
  gRadar.cluster.hidden_depend_funs{end+1} = {'array_proc_sv.m' 1};
  gRadar.cluster.hidden_depend_funs{end+1} = {'lever_arm.m' 1};
  gRadar.cluster.hidden_depend_funs{end+1} = {'doa_nonlcon.m' 1};
  gRadar.cluster.hidden_depend_funs{end+1} = {'burst_noise_corr.m' 1};
  gRadar.cluster.hidden_depend_funs{end+1} = {'burst_noise_bad_samples.m' 1};
  % =======================================================================
  % REMINDER: Run cluster_compile after making changes to this list!
  % =======================================================================

  % .path = used by the scheduler to build the file dependency path
  %   typically this is the same at .path
  gRadar.path = profile(cur_profile).path;
  % .path_override = used by the scheduler to build the file dependency
  %   path, however only files that also exist in the .path directory
  %   will be overwritten so that if a file only exists in .path_override
  %   it will not be included in the file dependency list
  gRadar.path_override = profile(cur_profile).path_override;
  % .param_path = parameter spreadsheet folder
  gRadar.param_path = profile(cur_profile).param_path;
  % .tmp_path = this is where personal temporary files will be stored (e.g.
  %   the picker should store files here)
  gRadar.tmp_path = profile(cur_profile).tmp_file_path;
  % .tmp_path = this is where global temporary files will be stored (e.g.
  %   create records, headers, etc. files should be stored here so that
  %   the process can be resumed by anyone without having to redo all
  %   the work or track down other people's temporary files)
  gRadar.opr_tmp_path = profile(cur_profile).opr_tmp_file_path;
  
  % .data_path = where the data is stored, the records and vectors files
  %   contain relative paths to the data from this base path
  gRadar.data_path = profile(cur_profile).data_path;
  % .data_support_path = where the support data is stored, the
  %   make_gps_* functions have relative paths to the data from here
  gRadar.data_support_path = profile(cur_profile).data_support_path;
  % .support_path = where the support data is stored, this includes
  %   radar configs, gps, vectors, records, frames, and GIS files
  gRadar.support_path = profile(cur_profile).support_path;
  % .out_path = where the output directories are stored (i.e. quick look,
  %   csarp, combine, pick, and post results)
  gRadar.out_path = profile(cur_profile).out_path;
  % .GIS_path = where GIS files are stored (e.g. Landsat-7 imagery)
  gRadar.gis_path = profile(cur_profile).gis_path;
  % .opr_file_lock_check: logical that determines if lock state should be
  %   checked
  if isfield(profile(cur_profile),'opr_file_lock_check')
    gRadar.opr_file_lock_check = profile(cur_profile).opr_file_lock_check;
  else
    gRadar.opr_file_lock_check = true;
  end
  % .opr_file_lock: logical that determines if lock state will be enabled
  %   when files are created
  if isfield(profile(cur_profile),'opr_file_lock')
    gRadar.opr_file_lock = profile(cur_profile).opr_file_lock;
  else
    gRadar.opr_file_lock = false;
  end
  % .slurm_jobs_path = where param structures are stored for slurm scripts
  if ~isfield(profile(cur_profile),'slurm_jobs_path')
    profile(cur_profile).slurm_jobs_path = '';
  end  
  gRadar.slurm_jobs_path = profile(cur_profile).slurm_jobs_path;  
  % .ops: structure of open polar server specific parameters
  if isfield(profile(cur_profile),'ops')
    gRadar.ops = profile(cur_profile).ops;
  end
  % .data: structure of data website specific parameters
  if isfield(profile(cur_profile),'data')
    gRadar.data = profile(cur_profile).data;
  end
  % .mat_file_version: options string to pass into opr_save
  if isfield(profile(cur_profile),'mat_file_version') ...
      && ~isempty(profile(cur_profile).mat_file_version)
    gRadar.mat_file_version = profile(cur_profile).mat_file_version;
  else
    gRadar.mat_file_version = '-v7.3'',''-nocompression';
  end
  
  clear profile cur_profile fn_dir fn_idx fn_name fns pidx;

else
  % fprintf('Compiling code: not running addpath in the compiled code\n');
end
