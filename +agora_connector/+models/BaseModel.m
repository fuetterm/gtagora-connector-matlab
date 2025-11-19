classdef BaseModel < dynamicprops
    %UNTITLED8 Summary of this class goes here
    %   Detailed explanation goes here
    
    properties(Abstract,Constant)
        BASE_URL;
    end
    
    properties
        http_client = [];
    end
    
    methods
        function self = BaseModel(http_client)
            if nargin > 0
                self.http_client = http_client;
            end
        end
        
        function self = get(self, id, http_client)
            if nargin < 2
                id = [];
            end
            if ~isempty(id)
                url = [self.BASE_URL, num2str(id), '/'];
            else
                url = self.BASE_URL;
            end
            if nargin > 2 && ~isempty(http_client)
                self.http_client = http_client;
            end            
            data = self.http_client.get(url);
            self = self.fill_from_data(data);                        
        end
        
        function objects = get_list(self, http_client, url, timeout)            
            if nargin > 1 && ~isempty(http_client)
                self.http_client = http_client;
            end   
            if nargin < 3
                url = [self.BASE_URL, '?limit=10000000000'];
            end
            if nargin < 4
                timeout = self.http_client.TIMEOUT;
            end
            if isempty(self.http_client)
                error('http client not set');
            end
            objects = [];
            data = self.http_client.get(url, timeout);
            if ~isempty(data)
                objects = fill_from_data_array(self, data);
            end                                    
        end
        
        function remove(self)
            url = [self.BASE_URL, num2str(self.id), '/'];
            self.http_client.delete(url);
        end
        
        function type = get_content_type(self)            
            if isa(self, 'agora_connector.models.Exam')
                type = 'exam';
            elseif isa(self, 'agora_connector.models.Folder')
                type = 'folder';
            elseif isa(self, 'agora_connector.models.Series')
                type = 'serie';
            elseif isa(self, 'agora_connector.models.Dataset')
                type = 'dataset';
            elseif isa(self, 'agora_connector.models.Patient')
                type = 'patient';
            else
                type = [];
            end
            
        end
        
        function self = fill_from_data(self, data)
            fn = fieldnames(data);
            for i = 1:length(fn)
                if ~isprop(self,fn{i})
                    self.addprop(fn{i});
                end
                self.(fn{i}) = data.(fn{i});
            end
        end
        
        function object_list = fill_from_data_array(self, data)            
            if isfield(data, 'results') && isfield(data, 'count')
                results = data.results;
                if data.count == 0
                    object_list = [];
                    return;
                end
                if data.count ~= length(results)
                    warning('could not get all results');
                end
                
                object_list(length(results)) = feval( class(self) );
                for i = 1:length(results)
                    object_list(i) = object_list(i).fill_from_data(results(i));
                    object_list(i).http_client = self.http_client;
                end
            elseif length(data) > 1
                object_list(length(data)) = feval( class(self) );
                for i = 1:length(data)
                    object_list(i) = object_list(i).fill_from_data(data(i));
                    object_list(i).http_client = self.http_client;
                end
            elseif ~isempty(data)
                object_list = self.fill_from_data(data);
                object_list.http_client = self.http_client;
            else
                object_list = [];
                return;
            end
        end
                        
        function name = get_class_name(self, full)
            if nargin < 2
                full = false;
            end
            name = class(self);
            if ~full
                splitted = strsplit(name,'.');
                name = splitted{end};
            end
        end
    end
                    
    methods (Static)
        function path = remove_illegal_chars(path)
            illegal = [':', '*', '"', '<', '>', '|'];
            
            for i = 1:length(illegal)
                path = strrep(path, illegal(i), '');
            end
        end

        function url = add_filter(url, filters)
            for i = 1:length(filters)
                if ~isa(filters(i), 'agora_connector.models.Filter')
                    error('the filter must be of class "agora_connector.models.Filter"');
                end                
                if strcmpi(filters(i).operator, 'exact')
                    url = [url, '&', filters(i).field, '=', num2str(filters(i).value)];
                else                
                    url = [url, '&', filters(i).field, '__', filters(i).operator, '=', num2str(filters(i).value)];
                end
            end
        end
    end
end

