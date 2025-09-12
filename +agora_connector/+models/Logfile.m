classdef Logfile < agora_connector.models.BaseModel
    %UNTITLED9 Summary of this class goes here
    %   Detailed explanation goes here

    properties
    end

    properties (Constant)
        BASE_URL = '/api/v2/logfile/';
    end

    methods
        function  content = get_content(self)
            url = [self.BASE_URL, num2str(self.id), '/content/'];
            content = self.http_client.get(url);
        end

        function [traffic, traffic_old] = parse_traffic(self, interval_sec)
            if nargin == 1
                interval_sec = 3600;           
            end

            traffic = [];
            traffic_old = [];
            if ~contains(self.filename, 'agora-runserver')
                return;
            end

            % Regular expression pattern to match the log entries
            log_pattern = '\[(?<timestamp>[^\]]+)\] INFO \[agora\.core\.middleware:\d+\] Request path: (?<path>[^,]+), Method: (?<method>[^,]+), User: (?<user>[^,]+), IP: (?<ip>[^,]+), Status code: (?<status_code>\d+), Response size: (?<response_size>\d+) bytes, Duration: (?<duration>[\d.]+) seconds';
            log_pattern_old = '(?<ip>[^,:]+(:\d+)?) - - \[(?<timestamp>[^\]]+)\] "(?<method>[^ ]+) (?<path>[^ ]+)" (?<status_code>\d+)';

            content = self.get_content();          
            traffic = regexp(content, log_pattern, 'names');                              
            traffic_old = regexp(content, log_pattern_old, 'names');                        
            if isempty(traffic) && isempty(traffic_old) 
                error('no traffic data found');                
            end               
        end
    end

    methods (Static)
        function plot_traffic(requests, interval_sec, last_days)
            if nargin < 2
                interval = hours(1);
                last_days = 14;                
            elseif nargin < 3
                last_days = 14;      
            else
                interval = seconds(interval_sec);
            end

            currentDate = datetime('now');
            thresholdDate = currentDate - days(last_days);

            has_size = isfield(requests, 'response_size');
            has_dur = isfield(requests, 'duration');
            has_user = isfield(requests, 'user');

            % Convert timestamps to datetime
            try
                timestamps = datetime({requests.timestamp}, 'InputFormat', 'dd/MMM/yyyy HH:mm:ss');
            catch
                timestamps = datetime({requests.timestamp}, 'InputFormat', 'dd/MMM/yyyy:HH:mm:ss');
            end
            
            requests = requests(timestamps > thresholdDate);
            timestamps = timestamps(timestamps > thresholdDate);            

            % Generate time intervals (e.g., hourly)
            edges = min(timestamps):interval:max(timestamps) + interval;
            numIntervals = length(edges) - 1;

            % Count number of requests per interval
            requestCounts = histcounts(timestamps, edges);

            % Prepare data for plotting
            if has_size
                responseSizes = str2double({requests.response_size})./1024;
                responseTimestamps = timestamps(responseSizes>0);
                responseSizes = responseSizes(responseSizes>0);
            end
            if has_dur
                durations = str2double({requests.duration});
                durationsTimestamps = timestamps(durations>0);
                durations = durations(durations>0);
            end

            if has_user
                uniqueUsers = unique({requests.user});
                numUsers = length(uniqueUsers);
                userCounts = zeros(numUsers, numIntervals);
                % Precompute user comparison logical matrix
                userLogicals = false(numUsers, length(requests));
                for j = 1:numUsers
                    userLogicals(j, :) = strcmp({requests.user}, uniqueUsers{j});
                end

                % Precompute the indices for time intervals
                intervalIdx = discretize(timestamps, edges);

                % Aggregate data
                for i = 1:numIntervals
                    idx = intervalIdx == i;
                    userCounts(:, i) = sum(idx & userLogicals, 2);
                end

                totalUserRequests = sum(userCounts, 2);
            end

            rows = 2 + has_size + has_dur + 2* has_user;
            cols = 1;

            % plot the request count depending on the path in a seperate window
            [paths, top_paths] = agora_connector.models.Logfile.plotPathStatistics(requests);

            % Plot number of requests over time
            figure('WindowState', 'maximized');
            subplot(rows, cols, 1);
            bar(edges(1:end-1), requestCounts, 'FaceColor', 'blue');
            xlabel('Time');
            ylabel('Number of Requests');
            title('Number of Requests Over Time');

            % Plot the top five paths over time in different colors
            top_paths = top_paths(1:5);
            subplot(rows, cols, 2);
            topPathCountsOverTime = zeros(numIntervals, length(top_paths));
            for p = 1:length(top_paths)
                pathIdx = strcmp(paths, top_paths{p});
                topPathCountsOverTime(:, p) = histcounts(timestamps(pathIdx), edges);
            end

            bar(edges(1:end-1), topPathCountsOverTime, 'stacked');
            xlabel('Time');
            ylabel('Number of Requests');
            title('Top 5 Normalized Paths Over Time');
            legend(top_paths);

            if has_user
                % Plot number of requests per user
                subplot(rows, cols, 3);
                bar(edges(1:end-1), userCounts', 'stacked');
                xlabel('Time');
                ylabel('Number of Requests per User');
                title('Number of Requests per User Over Time');
                legend(uniqueUsers);
            end

            if has_size
                % Plot response size over time
                subplot(rows, cols, 4);
                plot(responseTimestamps, responseSizes, 'g.', 'MarkerSize', 8);
                xlabel('Time');
                ylabel('Response Size (KBbytes)');
                title('Response Size Over Time');
            end

            if has_dur
                % Plot duration over time
                subplot(rows, cols, 5);
                plot(durationsTimestamps, durations, 'r.', 'MarkerSize', 8);
                xlabel('Time');
                ylabel('Duration (s)');
                title('Duration Over Time');
            end

            if has_user
                % Plot total number of requests per user
                subplot(rows, cols, 6);
                bar(categorical(uniqueUsers), totalUserRequests, 'FaceColor', 'cyan');
                xlabel('User');
                ylabel('Number of Requests');
                title('Total Number of Requests per User');
            end


        end

        function [paths, top_paths] = plotPathStatistics(requests)
            % Normalize the paths by removing IDs
            paths = {requests.path};
            api_path_idx = startsWith(paths, '/api/v');            
            paths(api_path_idx) = strrep(paths(api_path_idx), '/api/v1/', '');
            paths(api_path_idx) = strrep(paths(api_path_idx), '/api/v2/', '');
            paths = regexprep(paths, '/\d+', '/:id');
            paths = regexprep(paths, '\?.*', '');

            % Count the number of requests per normalized path
            [uniquePaths, ~, pathIdx] = unique(paths);
            pathCounts = accumarray(pathIdx, 1);

            % Sort paths by the number of requests
            [pathCounts, sortIdx] = sort(pathCounts, 'descend');
            uniquePaths = uniquePaths(sortIdx);
            nonZeroLengthIndices = ~cellfun('isempty', uniquePaths);
            uniquePaths = uniquePaths(nonZeroLengthIndices);
            pathCounts = pathCounts(nonZeroLengthIndices);

            % only display the 20 largest requests
            if length(uniquePaths) > 50
                uniquePaths = uniquePaths(1:50);
                pathCounts = pathCounts(1:50);
            end

            pathCategories  = categorical(uniquePaths);
            pathCategories  = reordercats(pathCategories ,uniquePaths);

            % Plot the number of requests per normalized path
            figure('WindowState', 'maximized');
            bar(pathCategories , pathCounts, 'FaceColor', 'red');
            xlabel('Normalized Path');
            ylabel('Number of Requests');
            title('Number of Requests per Normalized Path');
            xtickangle(45); % Rotate x-axis labels for better readability

            top_paths = uniquePaths;
        end
    end
end
